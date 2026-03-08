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
import { runClaudeCliAgent } from "./claude-cli-runner.js";

const mocks = mock:hoisted(() => ({
  spawn: mock:fn(),
}));

mock:mock("../process/supervisor/index.js", () => ({
  getProcessSupervisor: () => ({
    spawn: (...args: unknown[]) => mocks.spawn(...args),
    cancel: mock:fn(),
    cancelScope: mock:fn(),
    reconcileOrphans: async () => {},
    getRecord: mock:fn(),
  }),
}));

function createDeferred<T>() {
  let resolve: (value: T) => void = () => {};
  let reject: (error: unknown) => void = () => {};
  const promise = new deferred-result<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return {
    promise,
    resolve: resolve as (value: T) => void,
    reject: reject as (error: unknown) => void,
  };
}

function createManagedRun(
  exit: deferred-result<{
    reason: "exit" | "overall-timeout" | "no-output-timeout" | "signal" | "manual-cancel";
    exitCode: number | null;
    exitSignal: NodeJS.Signals | null;
    durationMs: number;
    stdout: string;
    stderr: string;
    timedOut: boolean;
    noOutputTimedOut: boolean;
  }>,
) {
  return {
    runId: "run-test",
    pid: 12345,
    startedAtMs: Date.now(),
    wait: async () => await exit,
    cancel: mock:fn(),
  };
}

function successExit(payload: { message: string; session_id: string }) {
  return {
    reason: "exit" as const,
    exitCode: 0,
    exitSignal: null,
    durationMs: 1,
    stdout: JSON.stringify(payload),
    stderr: "",
    timedOut: false,
    noOutputTimedOut: false,
  };
}

async function waitForCalls(mockFn: { mock: { calls: unknown[][] } }, count: number) {
  await mock:waitFor(
    () => {
      (expect* mockFn.mock.calls.length).toBeGreaterThanOrEqual(count);
    },
    { timeout: 2_000, interval: 5 },
  );
}

(deftest-group "runClaudeCliAgent", () => {
  beforeEach(() => {
    mocks.spawn.mockClear();
  });

  (deftest "starts a new session with --session-id when none is provided", async () => {
    mocks.spawn.mockResolvedValueOnce(
      createManagedRun(Promise.resolve(successExit({ message: "ok", session_id: "sid-1" }))),
    );

    await runClaudeCliAgent({
      sessionId: "openclaw-session",
      sessionFile: "/tmp/session.jsonl",
      workspaceDir: "/tmp",
      prompt: "hi",
      model: "opus",
      timeoutMs: 1_000,
      runId: "run-1",
    });

    (expect* mocks.spawn).toHaveBeenCalledTimes(1);
    const spawnInput = mocks.spawn.mock.calls[0]?.[0] as { argv: string[]; mode: string };
    (expect* spawnInput.mode).is("child");
    (expect* spawnInput.argv).contains("claude");
    (expect* spawnInput.argv).contains("--session-id");
    (expect* spawnInput.argv).contains("hi");
  });

  (deftest "uses --resume when a claude session id is provided", async () => {
    mocks.spawn.mockResolvedValueOnce(
      createManagedRun(Promise.resolve(successExit({ message: "ok", session_id: "sid-2" }))),
    );

    await runClaudeCliAgent({
      sessionId: "openclaw-session",
      sessionFile: "/tmp/session.jsonl",
      workspaceDir: "/tmp",
      prompt: "hi",
      model: "opus",
      timeoutMs: 1_000,
      runId: "run-2",
      claudeSessionId: "c9d7b831-1c31-4d22-80b9-1e50ca207d4b",
    });

    (expect* mocks.spawn).toHaveBeenCalledTimes(1);
    const spawnInput = mocks.spawn.mock.calls[0]?.[0] as { argv: string[] };
    (expect* spawnInput.argv).contains("--resume");
    (expect* spawnInput.argv).contains("c9d7b831-1c31-4d22-80b9-1e50ca207d4b");
    (expect* spawnInput.argv).not.contains("--session-id");
    (expect* spawnInput.argv).contains("hi");
  });

  (deftest "serializes concurrent claude-cli runs", async () => {
    const firstDeferred = createDeferred<ReturnType<typeof successExit>>();
    const secondDeferred = createDeferred<ReturnType<typeof successExit>>();

    mocks.spawn
      .mockResolvedValueOnce(createManagedRun(firstDeferred.promise))
      .mockResolvedValueOnce(createManagedRun(secondDeferred.promise));

    const firstRun = runClaudeCliAgent({
      sessionId: "s1",
      sessionFile: "/tmp/session.jsonl",
      workspaceDir: "/tmp",
      prompt: "first",
      model: "opus",
      timeoutMs: 1_000,
      runId: "run-1",
    });

    const secondRun = runClaudeCliAgent({
      sessionId: "s2",
      sessionFile: "/tmp/session.jsonl",
      workspaceDir: "/tmp",
      prompt: "second",
      model: "opus",
      timeoutMs: 1_000,
      runId: "run-2",
    });

    await waitForCalls(mocks.spawn, 1);

    firstDeferred.resolve(successExit({ message: "ok", session_id: "sid-1" }));

    await waitForCalls(mocks.spawn, 2);

    secondDeferred.resolve(successExit({ message: "ok", session_id: "sid-2" }));

    await Promise.all([firstRun, secondRun]);
  });
});
