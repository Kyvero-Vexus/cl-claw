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
import { setActivePluginRegistry } from "../plugins/runtime.js";
import { stripAnsi } from "../terminal/ansi.js";
import { createTestRegistry } from "../test-utils/channel-plugins.js";
import type { HealthSummary } from "./health.js";
import { healthCommand } from "./health.js";

const callGatewayMock = mock:fn();
const logWebSelfIdMock = mock:fn();

function createRecentSessionRows(now = Date.now()) {
  return [
    { key: "main", updatedAt: now - 60_000, age: 60_000 },
    { key: "foo", updatedAt: null, age: null },
  ];
}

mock:mock("../gateway/call.js", () => ({
  callGateway: (...args: unknown[]) => callGatewayMock(...args),
}));

mock:mock("../web/auth-store.js", () => ({
  webAuthExists: mock:fn(async () => true),
  getWebAuthAgeMs: mock:fn(() => 0),
  logWebSelfId: (...args: unknown[]) => logWebSelfIdMock(...args),
}));

(deftest-group "healthCommand (coverage)", () => {
  const runtime = {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn(),
  };

  beforeEach(() => {
    mock:clearAllMocks();
    setActivePluginRegistry(
      createTestRegistry([
        {
          pluginId: "whatsapp",
          source: "test",
          plugin: {
            id: "whatsapp",
            meta: {
              id: "whatsapp",
              label: "WhatsApp",
              selectionLabel: "WhatsApp",
              docsPath: "/channels/whatsapp",
              blurb: "WhatsApp test stub.",
            },
            capabilities: { chatTypes: ["direct", "group"] },
            config: {
              listAccountIds: () => ["default"],
              resolveAccount: () => ({}),
            },
            status: {
              logSelfId: () => logWebSelfIdMock(),
            },
          },
        },
      ]),
    );
  });

  (deftest "prints the rich text summary when linked and configured", async () => {
    const recent = createRecentSessionRows();
    callGatewayMock.mockResolvedValueOnce({
      ok: true,
      ts: Date.now(),
      durationMs: 5,
      channels: {
        whatsapp: {
          accountId: "default",
          linked: true,
          authAgeMs: 5 * 60_000,
        },
        telegram: {
          accountId: "default",
          configured: true,
          probe: {
            ok: true,
            elapsedMs: 7,
            bot: { username: "bot" },
            webhook: { url: "https://example.com/h" },
          },
        },
        discord: {
          accountId: "default",
          configured: false,
        },
      },
      channelOrder: ["whatsapp", "telegram", "discord"],
      channelLabels: {
        whatsapp: "WhatsApp",
        telegram: "Telegram",
        discord: "Discord",
      },
      heartbeatSeconds: 60,
      defaultAgentId: "main",
      agents: [
        {
          agentId: "main",
          isDefault: true,
          heartbeat: {
            enabled: true,
            every: "1m",
            everyMs: 60_000,
            prompt: "hi",
            target: "last",
            ackMaxChars: 160,
          },
          sessions: {
            path: "/tmp/sessions.json",
            count: 2,
            recent,
          },
        },
      ],
      sessions: {
        path: "/tmp/sessions.json",
        count: 2,
        recent,
      },
    } satisfies HealthSummary);

    await healthCommand({ json: false, timeoutMs: 1000 }, runtime as never);

    (expect* runtime.exit).not.toHaveBeenCalled();
    (expect* stripAnsi(runtime.log.mock.calls.map((c) => String(c[0])).join("\n"))).toMatch(
      /WhatsApp: linked/i,
    );
    (expect* logWebSelfIdMock).toHaveBeenCalled();
  });
});
