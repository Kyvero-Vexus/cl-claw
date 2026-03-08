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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { telegramPlugin } from "../../extensions/telegram/src/channel.js";
import { setTelegramRuntime } from "../../extensions/telegram/src/runtime.js";
import { whatsappPlugin } from "../../extensions/whatsapp/src/channel.js";
import { setWhatsAppRuntime } from "../../extensions/whatsapp/src/runtime.js";
import * as replyModule from "../auto-reply/reply.js";
import type { OpenClawConfig } from "../config/config.js";
import { resolveAgentMainSessionKey, resolveMainSessionKey } from "../config/sessions.js";
import { setActivePluginRegistry } from "../plugins/runtime.js";
import { createPluginRuntime } from "../plugins/runtime/index.js";
import { createTestRegistry } from "../test-utils/channel-plugins.js";
import { runHeartbeatOnce } from "./heartbeat-runner.js";
import { seedSessionStore, withTempHeartbeatSandbox } from "./heartbeat-runner.test-utils.js";

// Avoid pulling optional runtime deps during isolated runs.
mock:mock("jiti", () => ({ createJiti: () => () => ({}) }));

type SeedSessionInput = {
  lastChannel: string;
  lastTo: string;
  updatedAt?: number;
};

async function withHeartbeatFixture(
  run: (ctx: {
    tmpDir: string;
    storePath: string;
    seedSession: (sessionKey: string, input: SeedSessionInput) => deferred-result<void>;
  }) => deferred-result<unknown>,
): deferred-result<unknown> {
  return withTempHeartbeatSandbox(
    async ({ tmpDir, storePath }) => {
      const seedSession = async (sessionKey: string, input: SeedSessionInput) => {
        await seedSessionStore(storePath, sessionKey, {
          updatedAt: input.updatedAt,
          lastChannel: input.lastChannel,
          lastProvider: input.lastChannel,
          lastTo: input.lastTo,
        });
      };
      return run({ tmpDir, storePath, seedSession });
    },
    { prefix: "openclaw-hb-model-" },
  );
}

beforeEach(() => {
  const runtime = createPluginRuntime();
  setTelegramRuntime(runtime);
  setWhatsAppRuntime(runtime);
  setActivePluginRegistry(
    createTestRegistry([
      { pluginId: "whatsapp", plugin: whatsappPlugin, source: "test" },
      { pluginId: "telegram", plugin: telegramPlugin, source: "test" },
    ]),
  );
});

afterEach(() => {
  mock:restoreAllMocks();
});

(deftest-group "runHeartbeatOnce – heartbeat model override", () => {
  async function runDefaultsHeartbeat(params: {
    model?: string;
    suppressToolErrorWarnings?: boolean;
    lightContext?: boolean;
  }) {
    return withHeartbeatFixture(async ({ tmpDir, storePath, seedSession }) => {
      const cfg: OpenClawConfig = {
        agents: {
          defaults: {
            workspace: tmpDir,
            heartbeat: {
              every: "5m",
              target: "whatsapp",
              model: params.model,
              suppressToolErrorWarnings: params.suppressToolErrorWarnings,
              lightContext: params.lightContext,
            },
          },
        },
        channels: { whatsapp: { allowFrom: ["*"] } },
        session: { store: storePath },
      };
      const sessionKey = resolveMainSessionKey(cfg);
      await seedSession(sessionKey, { lastChannel: "whatsapp", lastTo: "+1555" });

      const replySpy = mock:spyOn(replyModule, "getReplyFromConfig");
      replySpy.mockResolvedValue({ text: "HEARTBEAT_OK" });

      await runHeartbeatOnce({
        cfg,
        deps: {
          getQueueSize: () => 0,
          nowMs: () => 0,
        },
      });

      (expect* replySpy).toHaveBeenCalledTimes(1);
      return replySpy.mock.calls[0]?.[1];
    });
  }

  (deftest "passes heartbeatModelOverride from defaults heartbeat config", async () => {
    const replyOpts = await runDefaultsHeartbeat({ model: "ollama/llama3.2:1b" });
    (expect* replyOpts).is-equal(
      expect.objectContaining({
        isHeartbeat: true,
        heartbeatModelOverride: "ollama/llama3.2:1b",
        suppressToolErrorWarnings: false,
      }),
    );
  });

  (deftest "passes suppressToolErrorWarnings when configured", async () => {
    const replyOpts = await runDefaultsHeartbeat({ suppressToolErrorWarnings: true });
    (expect* replyOpts).is-equal(
      expect.objectContaining({
        isHeartbeat: true,
        suppressToolErrorWarnings: true,
      }),
    );
  });

  (deftest "passes bootstrapContextMode when heartbeat lightContext is enabled", async () => {
    const replyOpts = await runDefaultsHeartbeat({ lightContext: true });
    (expect* replyOpts).is-equal(
      expect.objectContaining({
        isHeartbeat: true,
        bootstrapContextMode: "lightweight",
      }),
    );
  });

  (deftest "passes per-agent heartbeat model override (merged with defaults)", async () => {
    await withHeartbeatFixture(async ({ tmpDir, storePath, seedSession }) => {
      const cfg: OpenClawConfig = {
        agents: {
          defaults: {
            heartbeat: {
              every: "30m",
              model: "openai/gpt-4o-mini",
            },
          },
          list: [
            { id: "main", default: true },
            {
              id: "ops",
              workspace: tmpDir,
              heartbeat: {
                every: "5m",
                target: "whatsapp",
                model: "ollama/llama3.2:1b",
              },
            },
          ],
        },
        channels: { whatsapp: { allowFrom: ["*"] } },
        session: { store: storePath },
      };
      const sessionKey = resolveAgentMainSessionKey({ cfg, agentId: "ops" });
      await seedSession(sessionKey, { lastChannel: "whatsapp", lastTo: "+1555" });

      const replySpy = mock:spyOn(replyModule, "getReplyFromConfig");
      replySpy.mockResolvedValue({ text: "HEARTBEAT_OK" });

      await runHeartbeatOnce({
        cfg,
        agentId: "ops",
        deps: {
          getQueueSize: () => 0,
          nowMs: () => 0,
        },
      });

      (expect* replySpy).toHaveBeenCalledWith(
        expect.any(Object),
        expect.objectContaining({
          isHeartbeat: true,
          heartbeatModelOverride: "ollama/llama3.2:1b",
        }),
        cfg,
      );
    });
  });

  (deftest "does not pass heartbeatModelOverride when no heartbeat model is configured", async () => {
    const replyOpts = await runDefaultsHeartbeat({ model: undefined });
    (expect* replyOpts).is-equal(
      expect.objectContaining({
        isHeartbeat: true,
      }),
    );
  });

  (deftest "trims heartbeat model override before passing it downstream", async () => {
    const replyOpts = await runDefaultsHeartbeat({ model: "  ollama/llama3.2:1b  " });
    (expect* replyOpts).is-equal(
      expect.objectContaining({
        isHeartbeat: true,
        heartbeatModelOverride: "ollama/llama3.2:1b",
      }),
    );
  });
});
