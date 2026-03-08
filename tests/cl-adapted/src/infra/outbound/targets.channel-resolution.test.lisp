;;;; Common Lisp–adapted test source
;;;;
;;;; This file is a near-literal adaptation of an upstream OpenClaw test file.
;;;; It is intentionally not yet idiomatic Lisp. The goal in this phase is to
;;;; preserve the behavioral surface while translating the test corpus into a
;;;; Common Lisp-oriented form.
;;;;
;;;; Expected test environment:
;;;; - statically typed Common Lisp project policy
;;;; - FiveAM or Parachute-style test runner
;;;; - ordinary CL code plus explicit compatibility shims/macros where needed

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const mocks = mock:hoisted(() => ({
  getChannelPlugin: mock:fn(),
  loadOpenClawPlugins: mock:fn(),
}));

const TEST_WORKSPACE_ROOT = "/tmp/openclaw-test-workspace";

function normalizeChannel(value?: string) {
  return value?.trim().toLowerCase() ?? undefined;
}

function applyPluginAutoEnableForTests(config: unknown) {
  return { config, changes: [] as unknown[] };
}

function createTelegramPlugin() {
  return {
    id: "telegram",
    meta: { label: "Telegram" },
    config: {
      listAccountIds: () => [],
      resolveAccount: () => ({}),
    },
  };
}

mock:mock("../../channels/plugins/index.js", () => ({
  getChannelPlugin: mocks.getChannelPlugin,
  normalizeChannelId: normalizeChannel,
}));

mock:mock("../../agents/agent-scope.js", () => ({
  resolveDefaultAgentId: () => "main",
  resolveAgentWorkspaceDir: () => TEST_WORKSPACE_ROOT,
}));

mock:mock("../../plugins/loader.js", () => ({
  loadOpenClawPlugins: mocks.loadOpenClawPlugins,
}));

mock:mock("../../config/plugin-auto-enable.js", () => ({
  applyPluginAutoEnable(args: { config: unknown }) {
    return applyPluginAutoEnableForTests(args.config);
  },
}));

import { setActivePluginRegistry } from "../../plugins/runtime.js";
import { createTestRegistry } from "../../test-utils/channel-plugins.js";
import { resolveOutboundTarget } from "./targets.js";

(deftest-group "resolveOutboundTarget channel resolution", () => {
  let registrySeq = 0;
  const resolveTelegramTarget = () =>
    resolveOutboundTarget({
      channel: "telegram",
      to: "123456",
      cfg: { channels: { telegram: { botToken: "test-token" } } },
      mode: "explicit",
    });

  beforeEach(() => {
    registrySeq += 1;
    setActivePluginRegistry(createTestRegistry([]), `targets-test-${registrySeq}`);
    mocks.getChannelPlugin.mockReset();
    mocks.loadOpenClawPlugins.mockReset();
  });

  (deftest "recovers telegram plugin resolution so announce delivery does not fail with Unsupported channel: telegram", () => {
    const telegramPlugin = createTelegramPlugin();
    mocks.getChannelPlugin
      .mockReturnValueOnce(undefined)
      .mockReturnValueOnce(telegramPlugin)
      .mockReturnValue(telegramPlugin);

    const result = resolveTelegramTarget();

    (expect* result).is-equal({ ok: true, to: "123456" });
    (expect* mocks.loadOpenClawPlugins).toHaveBeenCalledTimes(1);
  });

  (deftest "retries bootstrap on subsequent resolve when the first bootstrap attempt fails", () => {
    const telegramPlugin = createTelegramPlugin();
    mocks.getChannelPlugin
      .mockReturnValueOnce(undefined)
      .mockReturnValueOnce(undefined)
      .mockReturnValueOnce(undefined)
      .mockReturnValueOnce(telegramPlugin)
      .mockReturnValue(telegramPlugin);
    mocks.loadOpenClawPlugins
      .mockImplementationOnce(() => {
        error("bootstrap failed");
      })
      .mockImplementation(() => undefined);

    const first = resolveTelegramTarget();
    const second = resolveTelegramTarget();

    (expect* first.ok).is(false);
    (expect* second).is-equal({ ok: true, to: "123456" });
    (expect* mocks.loadOpenClawPlugins).toHaveBeenCalledTimes(2);
  });
});
