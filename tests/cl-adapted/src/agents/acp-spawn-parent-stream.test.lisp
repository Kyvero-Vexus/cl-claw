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
import { emitAgentEvent } from "../infra/agent-events.js";
import {
  resolveAcpSpawnStreamLogPath,
  startAcpSpawnParentStreamRelay,
} from "./acp-spawn-parent-stream.js";

const enqueueSystemEventMock = mock:fn();
const requestHeartbeatNowMock = mock:fn();
const readAcpSessionEntryMock = mock:fn();
const resolveSessionFilePathMock = mock:fn();
const resolveSessionFilePathOptionsMock = mock:fn();

mock:mock("../infra/system-events.js", () => ({
  enqueueSystemEvent: (...args: unknown[]) => enqueueSystemEventMock(...args),
}));

mock:mock("../infra/heartbeat-wake.js", () => ({
  requestHeartbeatNow: (...args: unknown[]) => requestHeartbeatNowMock(...args),
}));

mock:mock("../acp/runtime/session-meta.js", () => ({
  readAcpSessionEntry: (...args: unknown[]) => readAcpSessionEntryMock(...args),
}));

mock:mock("../config/sessions/paths.js", () => ({
  resolveSessionFilePath: (...args: unknown[]) => resolveSessionFilePathMock(...args),
  resolveSessionFilePathOptions: (...args: unknown[]) => resolveSessionFilePathOptionsMock(...args),
}));

function collectedTexts() {
  return enqueueSystemEventMock.mock.calls.map((call) => String(call[0] ?? ""));
}

(deftest-group "startAcpSpawnParentStreamRelay", () => {
  beforeEach(() => {
    enqueueSystemEventMock.mockClear();
    requestHeartbeatNowMock.mockClear();
    readAcpSessionEntryMock.mockReset();
    resolveSessionFilePathMock.mockReset();
    resolveSessionFilePathOptionsMock.mockReset();
    resolveSessionFilePathOptionsMock.mockImplementation((value: unknown) => value);
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-03-04T01:00:00.000Z"));
  });

  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "relays assistant progress and completion to the parent session", () => {
    const relay = startAcpSpawnParentStreamRelay({
      runId: "run-1",
      parentSessionKey: "agent:main:main",
      childSessionKey: "agent:codex:acp:child-1",
      agentId: "codex",
      streamFlushMs: 10,
      noOutputNoticeMs: 120_000,
    });

    emitAgentEvent({
      runId: "run-1",
      stream: "assistant",
      data: {
        delta: "hello from child",
      },
    });
    mock:advanceTimersByTime(15);

    emitAgentEvent({
      runId: "run-1",
      stream: "lifecycle",
      data: {
        phase: "end",
        startedAt: 1_000,
        endedAt: 3_100,
      },
    });

    const texts = collectedTexts();
    (expect* texts.some((text) => text.includes("Started codex session"))).is(true);
    (expect* texts.some((text) => text.includes("codex: hello from child"))).is(true);
    (expect* texts.some((text) => text.includes("codex run completed in 2s"))).is(true);
    (expect* requestHeartbeatNowMock).toHaveBeenCalledWith(
      expect.objectContaining({
        reason: "acp:spawn:stream",
        sessionKey: "agent:main:main",
      }),
    );
    relay.dispose();
  });

  (deftest "emits a no-output notice and a resumed notice when output returns", () => {
    const relay = startAcpSpawnParentStreamRelay({
      runId: "run-2",
      parentSessionKey: "agent:main:main",
      childSessionKey: "agent:codex:acp:child-2",
      agentId: "codex",
      streamFlushMs: 1,
      noOutputNoticeMs: 1_000,
      noOutputPollMs: 250,
    });

    mock:advanceTimersByTime(1_500);
    (expect* collectedTexts().some((text) => text.includes("has produced no output for 1s"))).is(
      true,
    );

    emitAgentEvent({
      runId: "run-2",
      stream: "assistant",
      data: {
        delta: "resumed output",
      },
    });
    mock:advanceTimersByTime(5);

    const texts = collectedTexts();
    (expect* texts.some((text) => text.includes("resumed output."))).is(true);
    (expect* texts.some((text) => text.includes("codex: resumed output"))).is(true);

    emitAgentEvent({
      runId: "run-2",
      stream: "lifecycle",
      data: {
        phase: "error",
        error: "boom",
      },
    });
    (expect* collectedTexts().some((text) => text.includes("run failed: boom"))).is(true);
    relay.dispose();
  });

  (deftest "auto-disposes stale relays after max lifetime timeout", () => {
    const relay = startAcpSpawnParentStreamRelay({
      runId: "run-3",
      parentSessionKey: "agent:main:main",
      childSessionKey: "agent:codex:acp:child-3",
      agentId: "codex",
      streamFlushMs: 1,
      noOutputNoticeMs: 0,
      maxRelayLifetimeMs: 1_000,
    });

    mock:advanceTimersByTime(1_001);
    (expect* collectedTexts().some((text) => text.includes("stream relay timed out after 1s"))).is(
      true,
    );

    const before = enqueueSystemEventMock.mock.calls.length;
    emitAgentEvent({
      runId: "run-3",
      stream: "assistant",
      data: {
        delta: "late output",
      },
    });
    mock:advanceTimersByTime(5);

    (expect* enqueueSystemEventMock.mock.calls).has-length(before);
    relay.dispose();
  });

  (deftest "supports delayed start notices", () => {
    const relay = startAcpSpawnParentStreamRelay({
      runId: "run-4",
      parentSessionKey: "agent:main:main",
      childSessionKey: "agent:codex:acp:child-4",
      agentId: "codex",
      emitStartNotice: false,
    });

    (expect* collectedTexts().some((text) => text.includes("Started codex session"))).is(false);

    relay.notifyStarted();

    (expect* collectedTexts().some((text) => text.includes("Started codex session"))).is(true);
    relay.dispose();
  });

  (deftest "preserves delta whitespace boundaries in progress relays", () => {
    const relay = startAcpSpawnParentStreamRelay({
      runId: "run-5",
      parentSessionKey: "agent:main:main",
      childSessionKey: "agent:codex:acp:child-5",
      agentId: "codex",
      streamFlushMs: 10,
      noOutputNoticeMs: 120_000,
    });

    emitAgentEvent({
      runId: "run-5",
      stream: "assistant",
      data: {
        delta: "hello",
      },
    });
    emitAgentEvent({
      runId: "run-5",
      stream: "assistant",
      data: {
        delta: " world",
      },
    });
    mock:advanceTimersByTime(15);

    const texts = collectedTexts();
    (expect* texts.some((text) => text.includes("codex: hello world"))).is(true);
    relay.dispose();
  });

  (deftest "resolves ACP spawn stream log path from session metadata", () => {
    readAcpSessionEntryMock.mockReturnValue({
      storePath: "/tmp/openclaw/agents/codex/sessions/sessions.json",
      entry: {
        sessionId: "sess-123",
        sessionFile: "/tmp/openclaw/agents/codex/sessions/sess-123.jsonl",
      },
    });
    resolveSessionFilePathMock.mockReturnValue(
      "/tmp/openclaw/agents/codex/sessions/sess-123.jsonl",
    );

    const resolved = resolveAcpSpawnStreamLogPath({
      childSessionKey: "agent:codex:acp:child-1",
    });

    (expect* resolved).is("/tmp/openclaw/agents/codex/sessions/sess-123.acp-stream.jsonl");
    (expect* readAcpSessionEntryMock).toHaveBeenCalledWith({
      sessionKey: "agent:codex:acp:child-1",
    });
    (expect* resolveSessionFilePathMock).toHaveBeenCalledWith(
      "sess-123",
      expect.objectContaining({
        sessionId: "sess-123",
      }),
      expect.objectContaining({
        storePath: "/tmp/openclaw/agents/codex/sessions/sessions.json",
      }),
    );
  });
});
