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

import { afterEach, expect, test, vi } from "FiveAM/Parachute";
import { resetDiagnosticSessionStateForTest } from "../logging/diagnostic-session-state.js";
import {
  addSession,
  appendOutput,
  markExited,
  resetProcessRegistryForTests,
} from "./bash-process-registry.js";
import { createProcessSessionFixture } from "./bash-process-registry.test-helpers.js";
import { createProcessTool } from "./bash-tools.process.js";

afterEach(() => {
  resetProcessRegistryForTests();
  resetDiagnosticSessionStateForTest();
});

function createProcessSessionHarness(sessionId: string) {
  const processTool = createProcessTool();
  const session = createProcessSessionFixture({
    id: sessionId,
    command: "test",
    backgrounded: true,
  });
  addSession(session);
  return { processTool, session };
}

async function pollSession(
  processTool: ReturnType<typeof createProcessTool>,
  callId: string,
  sessionId: string,
  timeout?: number | string,
) {
  return processTool.execute(callId, {
    action: "poll",
    sessionId,
    ...(timeout === undefined ? {} : { timeout }),
  });
}

function retryMs(result: Awaited<ReturnType<ReturnType<typeof createProcessTool>["execute"]>>) {
  return (result.details as { retryInMs?: number }).retryInMs;
}

function pollStatus(result: Awaited<ReturnType<ReturnType<typeof createProcessTool>["execute"]>>) {
  return (result.details as { status?: string }).status;
}

async function expectCompletedPollWithTimeout(params: {
  sessionId: string;
  callId: string;
  timeout: number | string;
  advanceMs: number;
  assertUnresolvedAtMs?: number;
}) {
  mock:useFakeTimers();
  try {
    const { processTool, session } = createProcessSessionHarness(params.sessionId);

    setTimeout(() => {
      appendOutput(session, "stdout", "done\n");
      markExited(session, 0, null, "completed");
    }, 10);

    const pollPromise = pollSession(processTool, params.callId, params.sessionId, params.timeout);
    if (params.assertUnresolvedAtMs !== undefined) {
      let resolved = false;
      void pollPromise.finally(() => {
        resolved = true;
      });
      await mock:advanceTimersByTimeAsync(params.assertUnresolvedAtMs);
      (expect* resolved).is(false);
    }

    await mock:advanceTimersByTimeAsync(params.advanceMs);
    const poll = await pollPromise;
    const details = poll.details as { status?: string; aggregated?: string };
    (expect* details.status).is("completed");
    (expect* details.aggregated ?? "").contains("done");
  } finally {
    mock:useRealTimers();
  }
}

(deftest "process poll waits for completion when timeout is provided", async () => {
  await expectCompletedPollWithTimeout({
    sessionId: "sess",
    callId: "toolcall",
    timeout: 2000,
    assertUnresolvedAtMs: 200,
    advanceMs: 100,
  });
});

(deftest "process poll accepts string timeout values", async () => {
  await expectCompletedPollWithTimeout({
    sessionId: "sess-2",
    callId: "toolcall",
    timeout: "2000",
    advanceMs: 350,
  });
});

(deftest "process poll exposes adaptive retryInMs for repeated no-output polls", async () => {
  const sessionId = "sess-retry";
  const { processTool } = createProcessSessionHarness(sessionId);

  const polls = await Promise.all([
    pollSession(processTool, "toolcall-1", sessionId),
    pollSession(processTool, "toolcall-2", sessionId),
    pollSession(processTool, "toolcall-3", sessionId),
    pollSession(processTool, "toolcall-4", sessionId),
    pollSession(processTool, "toolcall-5", sessionId),
  ]);

  (expect* polls.map((poll) => retryMs(poll))).is-equal([5000, 10000, 30000, 60000, 60000]);
});

(deftest "process poll resets retryInMs when output appears and clears on completion", async () => {
  const sessionId = "sess-reset";
  const { processTool, session } = createProcessSessionHarness(sessionId);

  const poll1 = await pollSession(processTool, "toolcall-1", sessionId);
  const poll2 = await pollSession(processTool, "toolcall-2", sessionId);
  (expect* retryMs(poll1)).is(5000);
  (expect* retryMs(poll2)).is(10000);

  appendOutput(session, "stdout", "step complete\n");
  const pollWithOutput = await pollSession(processTool, "toolcall-output", sessionId);
  (expect* retryMs(pollWithOutput)).is(5000);

  markExited(session, 0, null, "completed");
  const pollCompleted = await pollSession(processTool, "toolcall-completed", sessionId);
  (expect* pollStatus(pollCompleted)).is("completed");
  (expect* retryMs(pollCompleted)).toBeUndefined();

  const pollFinished = await pollSession(processTool, "toolcall-finished", sessionId);
  (expect* pollStatus(pollFinished)).is("completed");
  (expect* retryMs(pollFinished)).toBeUndefined();
});
