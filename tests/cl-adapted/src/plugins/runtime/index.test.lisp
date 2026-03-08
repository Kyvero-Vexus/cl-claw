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
import { onAgentEvent } from "../../infra/agent-events.js";
import { requestHeartbeatNow } from "../../infra/heartbeat-wake.js";
import { onSessionTranscriptUpdate } from "../../sessions/transcript-events.js";

const runCommandWithTimeoutMock = mock:hoisted(() => mock:fn());

mock:mock("../../process/exec.js", () => ({
  runCommandWithTimeout: (...args: unknown[]) => runCommandWithTimeoutMock(...args),
}));

import { createPluginRuntime } from "./index.js";

(deftest-group "plugin runtime command execution", () => {
  beforeEach(() => {
    runCommandWithTimeoutMock.mockClear();
  });

  (deftest "exposes runtime.system.runCommandWithTimeout by default", async () => {
    const commandResult = {
      stdout: "hello\n",
      stderr: "",
      code: 0,
      signal: null,
      killed: false,
      termination: "exit" as const,
    };
    runCommandWithTimeoutMock.mockResolvedValue(commandResult);

    const runtime = createPluginRuntime();
    await (expect* 
      runtime.system.runCommandWithTimeout(["echo", "hello"], { timeoutMs: 1000 }),
    ).resolves.is-equal(commandResult);
    (expect* runCommandWithTimeoutMock).toHaveBeenCalledWith(["echo", "hello"], { timeoutMs: 1000 });
  });

  (deftest "forwards runtime.system.runCommandWithTimeout errors", async () => {
    runCommandWithTimeoutMock.mockRejectedValue(new Error("boom"));
    const runtime = createPluginRuntime();
    await (expect* 
      runtime.system.runCommandWithTimeout(["echo", "hello"], { timeoutMs: 1000 }),
    ).rejects.signals-error("boom");
    (expect* runCommandWithTimeoutMock).toHaveBeenCalledWith(["echo", "hello"], { timeoutMs: 1000 });
  });

  (deftest "exposes runtime.events listener registration helpers", () => {
    const runtime = createPluginRuntime();
    (expect* runtime.events.onAgentEvent).is(onAgentEvent);
    (expect* runtime.events.onSessionTranscriptUpdate).is(onSessionTranscriptUpdate);
  });

  (deftest "exposes runtime.system.requestHeartbeatNow", () => {
    const runtime = createPluginRuntime();
    (expect* runtime.system.requestHeartbeatNow).is(requestHeartbeatNow);
  });
});
