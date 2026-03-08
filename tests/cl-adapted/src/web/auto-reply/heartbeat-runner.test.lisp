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
import type { getReplyFromConfig } from "../../auto-reply/reply.js";
import { HEARTBEAT_TOKEN } from "../../auto-reply/tokens.js";
import { redactIdentifier } from "../../logging/redact-identifier.js";
import type { sendMessageWhatsApp } from "../outbound.js";

const state = mock:hoisted(() => ({
  visibility: { showAlerts: true, showOk: true, useIndicator: false },
  store: {} as Record<string, { updatedAt?: number; sessionId?: string }>,
  snapshot: {
    key: "k",
    entry: { sessionId: "s1", updatedAt: 123 },
    fresh: false,
    resetPolicy: { mode: "none", atHour: null, idleMinutes: null },
    dailyResetAt: null as number | null,
    idleExpiresAt: null as number | null,
  },
  events: [] as unknown[],
  loggerInfoCalls: [] as unknown[][],
  loggerWarnCalls: [] as unknown[][],
  heartbeatInfoLogs: [] as string[],
  heartbeatWarnLogs: [] as string[],
}));

mock:mock("../../agents/current-time.js", () => ({
  appendCronStyleCurrentTimeLine: (body: string) =>
    `${body}\nCurrent time: 2026-02-15T00:00:00Z (mock)`,
}));

// Perf: this module otherwise pulls a large dependency graph that we don't need
// for these unit tests.
mock:mock("../../auto-reply/reply.js", () => ({
  getReplyFromConfig: mock:fn(async () => undefined),
}));

mock:mock("../../channels/plugins/whatsapp-heartbeat.js", () => ({
  resolveWhatsAppHeartbeatRecipients: () => [],
}));

mock:mock("../../config/config.js", () => ({
  loadConfig: () => ({ agents: { defaults: {} }, session: {} }),
}));

mock:mock("../../routing/session-key.js", () => ({
  normalizeMainKey: () => null,
}));

mock:mock("../../infra/heartbeat-visibility.js", () => ({
  resolveHeartbeatVisibility: () => state.visibility,
}));

mock:mock("../../config/sessions.js", () => ({
  loadSessionStore: () => state.store,
  resolveSessionKey: () => "k",
  resolveStorePath: () => "/tmp/store.json",
  updateSessionStore: async (_path: string, updater: (store: typeof state.store) => void) => {
    updater(state.store);
  },
}));

mock:mock("./session-snapshot.js", () => ({
  getSessionSnapshot: () => state.snapshot,
}));

mock:mock("../../infra/heartbeat-events.js", () => ({
  emitHeartbeatEvent: (event: unknown) => state.events.push(event),
  resolveIndicatorType: (status: string) => `indicator:${status}`,
}));

mock:mock("../../logging.js", () => ({
  getChildLogger: () => ({
    info: (...args: unknown[]) => state.loggerInfoCalls.push(args),
    warn: (...args: unknown[]) => state.loggerWarnCalls.push(args),
  }),
}));

mock:mock("./loggers.js", () => ({
  whatsappHeartbeatLog: {
    info: (msg: string) => state.heartbeatInfoLogs.push(msg),
    warn: (msg: string) => state.heartbeatWarnLogs.push(msg),
  },
}));

mock:mock("../reconnect.js", () => ({
  newConnectionId: () => "run-1",
}));

mock:mock("../outbound.js", () => ({
  sendMessageWhatsApp: mock:fn(async () => ({ messageId: "m1" })),
}));

mock:mock("../session.js", () => ({
  formatError: (err: unknown) => `ERR:${String(err)}`,
}));

(deftest-group "runWebHeartbeatOnce", () => {
  let senderMock: ReturnType<typeof mock:fn>;
  let sender: typeof sendMessageWhatsApp;
  let replyResolverMock: ReturnType<typeof mock:fn>;
  let replyResolver: typeof getReplyFromConfig;

  const getModules = async () => await import("./heartbeat-runner.js");
  const buildRunArgs = (overrides: Record<string, unknown> = {}) => ({
    cfg: { agents: { defaults: {} }, session: {} } as never,
    to: "+123",
    sender,
    replyResolver,
    ...overrides,
  });

  beforeEach(() => {
    state.visibility = { showAlerts: true, showOk: true, useIndicator: false };
    state.store = { k: { updatedAt: 999, sessionId: "s1" } };
    state.snapshot = {
      key: "k",
      entry: { sessionId: "s1", updatedAt: 123 },
      fresh: false,
      resetPolicy: { mode: "none", atHour: null, idleMinutes: null },
      dailyResetAt: null,
      idleExpiresAt: null,
    };
    state.events = [];
    state.loggerInfoCalls = [];
    state.loggerWarnCalls = [];
    state.heartbeatInfoLogs = [];
    state.heartbeatWarnLogs = [];

    senderMock = mock:fn(async () => ({ messageId: "m1" }));
    sender = senderMock as unknown as typeof sendMessageWhatsApp;
    replyResolverMock = mock:fn(async () => undefined);
    replyResolver = replyResolverMock as unknown as typeof getReplyFromConfig;
  });

  (deftest "supports manual override body dry-run without sending", async () => {
    const { runWebHeartbeatOnce } = await getModules();
    await runWebHeartbeatOnce(buildRunArgs({ overrideBody: "hello", dryRun: true }));
    (expect* senderMock).not.toHaveBeenCalled();
    (expect* state.events).has-length(0);
  });

  (deftest "sends HEARTBEAT_OK when reply is empty and showOk is enabled", async () => {
    const { runWebHeartbeatOnce } = await getModules();
    await runWebHeartbeatOnce(buildRunArgs());
    (expect* senderMock).toHaveBeenCalledWith("+123", HEARTBEAT_TOKEN, { verbose: false });
    (expect* state.events).is-equal(
      expect.arrayContaining([expect.objectContaining({ status: "ok-empty", silent: false })]),
    );
  });

  (deftest "injects a cron-style Current time line into the heartbeat prompt", async () => {
    const { runWebHeartbeatOnce } = await getModules();
    await runWebHeartbeatOnce(
      buildRunArgs({
        cfg: { agents: { defaults: { heartbeat: { prompt: "Ops check" } } }, session: {} } as never,
        dryRun: true,
      }),
    );
    (expect* replyResolver).toHaveBeenCalledTimes(1);
    const ctx = replyResolverMock.mock.calls[0]?.[0];
    (expect* ctx?.Body).contains("Ops check");
    (expect* ctx?.Body).contains("Current time: 2026-02-15T00:00:00Z (mock)");
  });

  (deftest "treats heartbeat token-only replies as ok-token and preserves session updatedAt", async () => {
    replyResolverMock.mockResolvedValue({ text: HEARTBEAT_TOKEN });
    const { runWebHeartbeatOnce } = await getModules();
    await runWebHeartbeatOnce(buildRunArgs());
    (expect* state.store.k?.updatedAt).is(123);
    (expect* senderMock).toHaveBeenCalledWith("+123", HEARTBEAT_TOKEN, { verbose: false });
    (expect* state.events).is-equal(
      expect.arrayContaining([expect.objectContaining({ status: "ok-token", silent: false })]),
    );
  });

  (deftest "skips sending alerts when showAlerts is disabled but still emits a skipped event", async () => {
    state.visibility = { showAlerts: false, showOk: true, useIndicator: true };
    replyResolverMock.mockResolvedValue({ text: "ALERT" });
    const { runWebHeartbeatOnce } = await getModules();
    await runWebHeartbeatOnce(buildRunArgs());
    (expect* senderMock).not.toHaveBeenCalled();
    (expect* state.events).is-equal(
      expect.arrayContaining([
        expect.objectContaining({ status: "skipped", reason: "alerts-disabled", preview: "ALERT" }),
      ]),
    );
  });

  (deftest "emits failed events when sending throws and rethrows the error", async () => {
    replyResolverMock.mockResolvedValue({ text: "ALERT" });
    senderMock.mockRejectedValueOnce(new Error("nope"));
    const { runWebHeartbeatOnce } = await getModules();
    await (expect* runWebHeartbeatOnce(buildRunArgs())).rejects.signals-error("nope");
    (expect* state.events).is-equal(
      expect.arrayContaining([
        expect.objectContaining({ status: "failed", reason: "ERR:Error: nope" }),
      ]),
    );
  });

  (deftest "redacts recipient and omits body preview in heartbeat logs", async () => {
    replyResolverMock.mockResolvedValue({ text: "sensitive heartbeat body" });
    const { runWebHeartbeatOnce } = await getModules();
    await runWebHeartbeatOnce(buildRunArgs({ dryRun: true }));

    const expected = redactIdentifier("+123");
    const heartbeatLogs = state.heartbeatInfoLogs.join("\n");
    const childLoggerLogs = state.loggerInfoCalls.map((entry) => JSON.stringify(entry)).join("\n");

    (expect* heartbeatLogs).contains(expected);
    (expect* heartbeatLogs).not.contains("+123");
    (expect* heartbeatLogs).not.contains("sensitive heartbeat body");

    (expect* childLoggerLogs).contains(expected);
    (expect* childLoggerLogs).not.contains("+123");
    (expect* childLoggerLogs).not.contains("sensitive heartbeat body");
    (expect* childLoggerLogs).not.contains('"preview"');
  });
});
