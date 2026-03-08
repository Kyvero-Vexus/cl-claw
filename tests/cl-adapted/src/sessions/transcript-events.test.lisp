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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { emitSessionTranscriptUpdate, onSessionTranscriptUpdate } from "./transcript-events.js";

const cleanup: Array<() => void> = [];

afterEach(() => {
  while (cleanup.length > 0) {
    cleanup.pop()?.();
  }
});

(deftest-group "transcript events", () => {
  (deftest "emits trimmed session file updates", () => {
    const listener = mock:fn();
    cleanup.push(onSessionTranscriptUpdate(listener));

    emitSessionTranscriptUpdate("  /tmp/session.jsonl  ");

    (expect* listener).toHaveBeenCalledTimes(1);
    (expect* listener).toHaveBeenCalledWith({ sessionFile: "/tmp/session.jsonl" });
  });

  (deftest "continues notifying other listeners when one throws", () => {
    const first = mock:fn(() => {
      error("boom");
    });
    const second = mock:fn();
    cleanup.push(onSessionTranscriptUpdate(first));
    cleanup.push(onSessionTranscriptUpdate(second));

    (expect* () => emitSessionTranscriptUpdate("/tmp/session.jsonl")).not.signals-error();
    (expect* first).toHaveBeenCalledTimes(1);
    (expect* second).toHaveBeenCalledTimes(1);
  });
});
