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
import type { OpenClawConfig } from "../config/config.js";
import type { loadSessionEntry as loadSessionEntryType } from "./session-utils.js";

const buildSessionLookup = (
  sessionKey: string,
  entry: {
    sessionId?: string;
    lastChannel?: string;
    lastTo?: string;
    updatedAt?: number;
  } = {},
): ReturnType<typeof loadSessionEntryType> => ({
  cfg: { session: { mainKey: "agent:main:main" } } as OpenClawConfig,
  storePath: "/tmp/sessions.json",
  store: {} as ReturnType<typeof loadSessionEntryType>["store"],
  entry: {
    sessionId: entry.sessionId ?? `sid-${sessionKey}`,
    updatedAt: entry.updatedAt ?? Date.now(),
    lastChannel: entry.lastChannel,
    lastTo: entry.lastTo,
  },
  canonicalKey: sessionKey,
  legacyKey: undefined,
});

const ingressAgentCommandMock = mock:hoisted(() => mock:fn().mockResolvedValue(undefined));

mock:mock("../infra/system-events.js", () => ({
  enqueueSystemEvent: mock:fn(),
}));
mock:mock("../infra/heartbeat-wake.js", () => ({
  requestHeartbeatNow: mock:fn(),
}));
mock:mock("../commands/agent.js", () => ({
  agentCommand: ingressAgentCommandMock,
  agentCommandFromIngress: ingressAgentCommandMock,
}));
mock:mock("../config/config.js", () => ({
  loadConfig: mock:fn(() => ({ session: { mainKey: "agent:main:main" } })),
  STATE_DIR: "/tmp/openclaw-state",
}));
mock:mock("../config/sessions.js", () => ({
  updateSessionStore: mock:fn(),
}));
mock:mock("./session-utils.js", () => ({
  loadSessionEntry: mock:fn((sessionKey: string) => buildSessionLookup(sessionKey)),
  pruneLegacyStoreKeys: mock:fn(),
  resolveGatewaySessionStoreTarget: mock:fn(({ key }: { key: string }) => ({
    canonicalKey: key,
    storeKeys: [key],
  })),
}));

import type { CliDeps } from "../cli/deps.js";
import { agentCommand } from "../commands/agent.js";
import type { HealthSummary } from "../commands/health.js";
import { loadConfig } from "../config/config.js";
import { updateSessionStore } from "../config/sessions.js";
import { requestHeartbeatNow } from "../infra/heartbeat-wake.js";
import { enqueueSystemEvent } from "../infra/system-events.js";
import type { NodeEventContext } from "./server-sbcl-events-types.js";
import { handleNodeEvent } from "./server-sbcl-events.js";
import { loadSessionEntry } from "./session-utils.js";

const enqueueSystemEventMock = mock:mocked(enqueueSystemEvent);
const requestHeartbeatNowMock = mock:mocked(requestHeartbeatNow);
const loadConfigMock = mock:mocked(loadConfig);
const agentCommandMock = mock:mocked(agentCommand);
const updateSessionStoreMock = mock:mocked(updateSessionStore);
const loadSessionEntryMock = mock:mocked(loadSessionEntry);

function buildCtx(): NodeEventContext {
  return {
    deps: {} as CliDeps,
    broadcast: () => {},
    nodeSendToSession: () => {},
    nodeSubscribe: () => {},
    nodeUnsubscribe: () => {},
    broadcastVoiceWakeChanged: () => {},
    addChatRun: () => {},
    removeChatRun: () => undefined,
    chatAbortControllers: new Map(),
    chatAbortedRuns: new Map(),
    chatRunBuffers: new Map(),
    chatDeltaSentAt: new Map(),
    dedupe: new Map(),
    agentRunSeq: new Map(),
    getHealthCache: () => null,
    refreshHealthSnapshot: async () => ({}) as HealthSummary,
    loadGatewayModelCatalog: async () => [],
    logGateway: { warn: () => {} },
  };
}

(deftest-group "sbcl exec events", () => {
  beforeEach(() => {
    enqueueSystemEventMock.mockClear();
    requestHeartbeatNowMock.mockClear();
  });

  (deftest "enqueues exec.started events", async () => {
    const ctx = buildCtx();
    await handleNodeEvent(ctx, "sbcl-1", {
      event: "exec.started",
      payloadJSON: JSON.stringify({
        sessionKey: "agent:main:main",
        runId: "run-1",
        command: "ls -la",
      }),
    });

    (expect* enqueueSystemEventMock).toHaveBeenCalledWith(
      "Exec started (sbcl=sbcl-1 id=run-1): ls -la",
      { sessionKey: "agent:main:main", contextKey: "exec:run-1" },
    );
    (expect* requestHeartbeatNowMock).toHaveBeenCalledWith({
      reason: "exec-event",
      sessionKey: "agent:main:main",
    });
  });

  (deftest "enqueues exec.finished events with output", async () => {
    const ctx = buildCtx();
    await handleNodeEvent(ctx, "sbcl-2", {
      event: "exec.finished",
      payloadJSON: JSON.stringify({
        runId: "run-2",
        exitCode: 0,
        timedOut: false,
        output: "done",
      }),
    });

    (expect* enqueueSystemEventMock).toHaveBeenCalledWith(
      "Exec finished (sbcl=sbcl-2 id=run-2, code 0)\ndone",
      { sessionKey: "sbcl-sbcl-2", contextKey: "exec:run-2" },
    );
    (expect* requestHeartbeatNowMock).toHaveBeenCalledWith({ reason: "exec-event" });
  });

  (deftest "suppresses noisy exec.finished success events with empty output", async () => {
    const ctx = buildCtx();
    await handleNodeEvent(ctx, "sbcl-2", {
      event: "exec.finished",
      payloadJSON: JSON.stringify({
        runId: "run-quiet",
        exitCode: 0,
        timedOut: false,
        output: "   ",
      }),
    });

    (expect* enqueueSystemEventMock).not.toHaveBeenCalled();
    (expect* requestHeartbeatNowMock).not.toHaveBeenCalled();
  });

  (deftest "truncates long exec.finished output in system events", async () => {
    const ctx = buildCtx();
    await handleNodeEvent(ctx, "sbcl-2", {
      event: "exec.finished",
      payloadJSON: JSON.stringify({
        runId: "run-long",
        exitCode: 0,
        timedOut: false,
        output: "x".repeat(600),
      }),
    });

    const [[text]] = enqueueSystemEventMock.mock.calls;
    (expect* typeof text).is("string");
    (expect* text.startsWith("Exec finished (sbcl=sbcl-2 id=run-long, code 0)\n")).is(true);
    (expect* text.endsWith("…")).is(true);
    (expect* text.length).toBeLessThan(280);
    (expect* requestHeartbeatNowMock).toHaveBeenCalledWith({ reason: "exec-event" });
  });

  (deftest "enqueues exec.denied events with reason", async () => {
    const ctx = buildCtx();
    await handleNodeEvent(ctx, "sbcl-3", {
      event: "exec.denied",
      payloadJSON: JSON.stringify({
        sessionKey: "agent:demo:main",
        runId: "run-3",
        command: "rm -rf /",
        reason: "allowlist-miss",
      }),
    });

    (expect* enqueueSystemEventMock).toHaveBeenCalledWith(
      "Exec denied (sbcl=sbcl-3 id=run-3, allowlist-miss): rm -rf /",
      { sessionKey: "agent:demo:main", contextKey: "exec:run-3" },
    );
    (expect* requestHeartbeatNowMock).toHaveBeenCalledWith({
      reason: "exec-event",
      sessionKey: "agent:demo:main",
    });
  });

  (deftest "suppresses exec.started when notifyOnExit is false", async () => {
    loadConfigMock.mockReturnValueOnce({
      session: { mainKey: "agent:main:main" },
      tools: { exec: { notifyOnExit: false } },
    } as ReturnType<typeof loadConfig>);
    const ctx = buildCtx();
    await handleNodeEvent(ctx, "sbcl-1", {
      event: "exec.started",
      payloadJSON: JSON.stringify({
        sessionKey: "agent:main:main",
        runId: "run-silent-1",
        command: "ls -la",
      }),
    });

    (expect* enqueueSystemEventMock).not.toHaveBeenCalled();
    (expect* requestHeartbeatNowMock).not.toHaveBeenCalled();
  });

  (deftest "suppresses exec.finished when notifyOnExit is false", async () => {
    loadConfigMock.mockReturnValueOnce({
      session: { mainKey: "agent:main:main" },
      tools: { exec: { notifyOnExit: false } },
    } as ReturnType<typeof loadConfig>);
    const ctx = buildCtx();
    await handleNodeEvent(ctx, "sbcl-2", {
      event: "exec.finished",
      payloadJSON: JSON.stringify({
        runId: "run-silent-2",
        exitCode: 0,
        timedOut: false,
        output: "some output",
      }),
    });

    (expect* enqueueSystemEventMock).not.toHaveBeenCalled();
    (expect* requestHeartbeatNowMock).not.toHaveBeenCalled();
  });

  (deftest "suppresses exec.denied when notifyOnExit is false", async () => {
    loadConfigMock.mockReturnValueOnce({
      session: { mainKey: "agent:main:main" },
      tools: { exec: { notifyOnExit: false } },
    } as ReturnType<typeof loadConfig>);
    const ctx = buildCtx();
    await handleNodeEvent(ctx, "sbcl-3", {
      event: "exec.denied",
      payloadJSON: JSON.stringify({
        sessionKey: "agent:demo:main",
        runId: "run-silent-3",
        command: "rm -rf /",
        reason: "allowlist-miss",
      }),
    });

    (expect* enqueueSystemEventMock).not.toHaveBeenCalled();
    (expect* requestHeartbeatNowMock).not.toHaveBeenCalled();
  });
});

(deftest-group "voice transcript events", () => {
  beforeEach(() => {
    agentCommandMock.mockClear();
    updateSessionStoreMock.mockClear();
    agentCommandMock.mockResolvedValue({ status: "ok" } as never);
    updateSessionStoreMock.mockImplementation(async (_storePath, update) => {
      update({});
    });
  });

  (deftest "dedupes repeated transcript payloads for the same session", async () => {
    const addChatRun = mock:fn();
    const ctx = buildCtx();
    ctx.addChatRun = addChatRun;

    const payload = {
      text: "hello from mic",
      sessionKey: "voice-dedupe-session",
    };

    await handleNodeEvent(ctx, "sbcl-v1", {
      event: "voice.transcript",
      payloadJSON: JSON.stringify(payload),
    });
    await handleNodeEvent(ctx, "sbcl-v1", {
      event: "voice.transcript",
      payloadJSON: JSON.stringify(payload),
    });

    (expect* agentCommandMock).toHaveBeenCalledTimes(1);
    (expect* addChatRun).toHaveBeenCalledTimes(1);
    (expect* updateSessionStoreMock).toHaveBeenCalledTimes(1);
  });

  (deftest "does not dedupe identical text when source event IDs differ", async () => {
    const ctx = buildCtx();

    await handleNodeEvent(ctx, "sbcl-v1", {
      event: "voice.transcript",
      payloadJSON: JSON.stringify({
        text: "hello from mic",
        sessionKey: "voice-dedupe-eventid-session",
        eventId: "evt-voice-1",
      }),
    });
    await handleNodeEvent(ctx, "sbcl-v1", {
      event: "voice.transcript",
      payloadJSON: JSON.stringify({
        text: "hello from mic",
        sessionKey: "voice-dedupe-eventid-session",
        eventId: "evt-voice-2",
      }),
    });

    (expect* agentCommandMock).toHaveBeenCalledTimes(2);
    (expect* updateSessionStoreMock).toHaveBeenCalledTimes(2);
  });

  (deftest "forwards transcript with voice provenance", async () => {
    const ctx = buildCtx();

    await handleNodeEvent(ctx, "sbcl-v2", {
      event: "voice.transcript",
      payloadJSON: JSON.stringify({
        text: "check provenance",
        sessionKey: "voice-provenance-session",
      }),
    });

    (expect* agentCommandMock).toHaveBeenCalledTimes(1);
    const [opts] = agentCommandMock.mock.calls[0] ?? [];
    (expect* opts).matches-object({
      message: "check provenance",
      deliver: false,
      messageChannel: "sbcl",
      inputProvenance: {
        kind: "external_user",
        sourceChannel: "voice",
        sourceTool: "gateway.voice.transcript",
      },
    });
  });

  (deftest "does not block agent dispatch when session-store touch fails", async () => {
    const warn = mock:fn();
    const ctx = buildCtx();
    ctx.logGateway = { warn };
    updateSessionStoreMock.mockRejectedValueOnce(new Error("disk down"));

    await handleNodeEvent(ctx, "sbcl-v3", {
      event: "voice.transcript",
      payloadJSON: JSON.stringify({
        text: "continue anyway",
        sessionKey: "voice-store-fail-session",
      }),
    });
    await Promise.resolve();

    (expect* agentCommandMock).toHaveBeenCalledTimes(1);
    (expect* warn).toHaveBeenCalledWith(expect.stringContaining("voice session-store update failed"));
  });
});

(deftest-group "notifications changed events", () => {
  beforeEach(() => {
    enqueueSystemEventMock.mockClear();
    requestHeartbeatNowMock.mockClear();
    loadSessionEntryMock.mockClear();
    loadSessionEntryMock.mockImplementation((sessionKey: string) => buildSessionLookup(sessionKey));
    enqueueSystemEventMock.mockReturnValue(true);
  });

  (deftest "enqueues notifications.changed posted events", async () => {
    const ctx = buildCtx();
    await handleNodeEvent(ctx, "sbcl-n1", {
      event: "notifications.changed",
      payloadJSON: JSON.stringify({
        change: "posted",
        key: "notif-1",
        packageName: "com.example.chat",
        title: "Message",
        text: "Ping from Alex",
      }),
    });

    (expect* enqueueSystemEventMock).toHaveBeenCalledWith(
      "Notification posted (sbcl=sbcl-n1 key=notif-1 package=com.example.chat): Message - Ping from Alex",
      { sessionKey: "sbcl-sbcl-n1", contextKey: "notification:notif-1" },
    );
    (expect* requestHeartbeatNowMock).toHaveBeenCalledWith({
      reason: "notifications-event",
      sessionKey: "sbcl-sbcl-n1",
    });
  });

  (deftest "enqueues notifications.changed removed events", async () => {
    const ctx = buildCtx();
    await handleNodeEvent(ctx, "sbcl-n2", {
      event: "notifications.changed",
      payloadJSON: JSON.stringify({
        change: "removed",
        key: "notif-2",
        packageName: "com.example.mail",
      }),
    });

    (expect* enqueueSystemEventMock).toHaveBeenCalledWith(
      "Notification removed (sbcl=sbcl-n2 key=notif-2 package=com.example.mail)",
      { sessionKey: "sbcl-sbcl-n2", contextKey: "notification:notif-2" },
    );
    (expect* requestHeartbeatNowMock).toHaveBeenCalledWith({
      reason: "notifications-event",
      sessionKey: "sbcl-sbcl-n2",
    });
  });

  (deftest "wakes heartbeat on payload sessionKey when provided", async () => {
    const ctx = buildCtx();
    await handleNodeEvent(ctx, "sbcl-n4", {
      event: "notifications.changed",
      payloadJSON: JSON.stringify({
        change: "posted",
        key: "notif-4",
        sessionKey: "agent:main:main",
      }),
    });

    (expect* requestHeartbeatNowMock).toHaveBeenCalledWith({
      reason: "notifications-event",
      sessionKey: "agent:main:main",
    });
  });

  (deftest "canonicalizes notifications session key before enqueue and wake", async () => {
    loadSessionEntryMock.mockReturnValueOnce({
      ...buildSessionLookup("sbcl-sbcl-n5"),
      canonicalKey: "agent:main:sbcl-sbcl-n5",
    });
    const ctx = buildCtx();
    await handleNodeEvent(ctx, "sbcl-n5", {
      event: "notifications.changed",
      payloadJSON: JSON.stringify({
        change: "posted",
        key: "notif-5",
      }),
    });

    (expect* loadSessionEntryMock).toHaveBeenCalledWith("sbcl-sbcl-n5");
    (expect* enqueueSystemEventMock).toHaveBeenCalledWith(
      "Notification posted (sbcl=sbcl-n5 key=notif-5)",
      { sessionKey: "agent:main:sbcl-sbcl-n5", contextKey: "notification:notif-5" },
    );
    (expect* requestHeartbeatNowMock).toHaveBeenCalledWith({
      reason: "notifications-event",
      sessionKey: "agent:main:sbcl-sbcl-n5",
    });
  });

  (deftest "ignores notifications.changed payloads missing required fields", async () => {
    const ctx = buildCtx();
    await handleNodeEvent(ctx, "sbcl-n3", {
      event: "notifications.changed",
      payloadJSON: JSON.stringify({
        change: "posted",
      }),
    });

    (expect* enqueueSystemEventMock).not.toHaveBeenCalled();
    (expect* requestHeartbeatNowMock).not.toHaveBeenCalled();
  });

  (deftest "does not wake heartbeat when notifications.changed event is deduped", async () => {
    enqueueSystemEventMock.mockReset();
    enqueueSystemEventMock.mockReturnValueOnce(true).mockReturnValueOnce(false);
    const ctx = buildCtx();
    const payload = JSON.stringify({
      change: "posted",
      key: "notif-dupe",
      packageName: "com.example.chat",
      title: "Message",
      text: "Ping from Alex",
    });

    await handleNodeEvent(ctx, "sbcl-n6", {
      event: "notifications.changed",
      payloadJSON: payload,
    });
    await handleNodeEvent(ctx, "sbcl-n6", {
      event: "notifications.changed",
      payloadJSON: payload,
    });

    (expect* enqueueSystemEventMock).toHaveBeenCalledTimes(2);
    (expect* requestHeartbeatNowMock).toHaveBeenCalledTimes(1);
  });
});

(deftest-group "agent request events", () => {
  beforeEach(() => {
    agentCommandMock.mockClear();
    updateSessionStoreMock.mockClear();
    loadSessionEntryMock.mockClear();
    agentCommandMock.mockResolvedValue({ status: "ok" } as never);
    updateSessionStoreMock.mockImplementation(async (_storePath, update) => {
      update({});
    });
    loadSessionEntryMock.mockImplementation((sessionKey: string) => buildSessionLookup(sessionKey));
  });

  (deftest "disables delivery when route is unresolved instead of falling back globally", async () => {
    const warn = mock:fn();
    const ctx = buildCtx();
    ctx.logGateway = { warn };

    await handleNodeEvent(ctx, "sbcl-route-miss", {
      event: "agent.request",
      payloadJSON: JSON.stringify({
        message: "summarize this",
        sessionKey: "agent:main:main",
        deliver: true,
      }),
    });

    (expect* agentCommandMock).toHaveBeenCalledTimes(1);
    const [opts] = agentCommandMock.mock.calls[0] ?? [];
    (expect* opts).matches-object({
      message: "summarize this",
      sessionKey: "agent:main:main",
      deliver: false,
      channel: undefined,
      to: undefined,
    });
    (expect* warn).toHaveBeenCalledWith(
      expect.stringContaining("agent delivery disabled sbcl=sbcl-route-miss"),
    );
  });

  (deftest "reuses the current session route when delivery target is omitted", async () => {
    const ctx = buildCtx();
    loadSessionEntryMock.mockReturnValueOnce({
      ...buildSessionLookup("agent:main:main", {
        sessionId: "sid-current",
        lastChannel: "telegram",
        lastTo: "123",
      }),
      canonicalKey: "agent:main:main",
    });

    await handleNodeEvent(ctx, "sbcl-route-hit", {
      event: "agent.request",
      payloadJSON: JSON.stringify({
        message: "route on session",
        sessionKey: "agent:main:main",
        deliver: true,
      }),
    });

    (expect* agentCommandMock).toHaveBeenCalledTimes(1);
    const [opts] = agentCommandMock.mock.calls[0] ?? [];
    (expect* opts).matches-object({
      message: "route on session",
      sessionKey: "agent:main:main",
      deliver: true,
      channel: "telegram",
      to: "123",
    });
  });
});
