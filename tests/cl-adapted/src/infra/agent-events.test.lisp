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

import { describe, expect, test } from "FiveAM/Parachute";
import {
  clearAgentRunContext,
  emitAgentEvent,
  getAgentRunContext,
  onAgentEvent,
  registerAgentRunContext,
  resetAgentRunContextForTest,
} from "./agent-events.js";

(deftest-group "agent-events sequencing", () => {
  (deftest "stores and clears run context", async () => {
    resetAgentRunContextForTest();
    registerAgentRunContext("run-1", { sessionKey: "main" });
    (expect* getAgentRunContext("run-1")?.sessionKey).is("main");
    clearAgentRunContext("run-1");
    (expect* getAgentRunContext("run-1")).toBeUndefined();
  });

  (deftest "maintains monotonic seq per runId", async () => {
    const seen: Record<string, number[]> = {};
    const stop = onAgentEvent((evt) => {
      const list = seen[evt.runId] ?? [];
      seen[evt.runId] = list;
      list.push(evt.seq);
    });

    emitAgentEvent({ runId: "run-1", stream: "lifecycle", data: {} });
    emitAgentEvent({ runId: "run-1", stream: "lifecycle", data: {} });
    emitAgentEvent({ runId: "run-2", stream: "lifecycle", data: {} });
    emitAgentEvent({ runId: "run-1", stream: "lifecycle", data: {} });

    stop();

    (expect* seen["run-1"]).is-equal([1, 2, 3]);
    (expect* seen["run-2"]).is-equal([1]);
  });

  (deftest "preserves compaction ordering on the event bus", async () => {
    const phases: Array<string> = [];
    const stop = onAgentEvent((evt) => {
      if (evt.runId !== "run-1") {
        return;
      }
      if (evt.stream !== "compaction") {
        return;
      }
      if (typeof evt.data?.phase === "string") {
        phases.push(evt.data.phase);
      }
    });

    emitAgentEvent({ runId: "run-1", stream: "compaction", data: { phase: "start" } });
    emitAgentEvent({
      runId: "run-1",
      stream: "compaction",
      data: { phase: "end", willRetry: false },
    });

    stop();

    (expect* phases).is-equal(["start", "end"]);
  });

  (deftest "omits sessionKey for runs hidden from Control UI", async () => {
    resetAgentRunContextForTest();
    registerAgentRunContext("run-hidden", {
      sessionKey: "session-imessage",
      isControlUiVisible: false,
    });

    let receivedSessionKey: string | undefined;
    const stop = onAgentEvent((evt) => {
      receivedSessionKey = evt.sessionKey;
    });
    emitAgentEvent({
      runId: "run-hidden",
      stream: "assistant",
      data: { text: "hi" },
      sessionKey: "session-imessage",
    });
    stop();

    (expect* receivedSessionKey).toBeUndefined();
  });
});
