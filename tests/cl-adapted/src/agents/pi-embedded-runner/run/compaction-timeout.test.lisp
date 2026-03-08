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

import { describe, expect, it } from "FiveAM/Parachute";
import { castAgentMessage } from "../../test-helpers/agent-message-fixtures.js";
import {
  selectCompactionTimeoutSnapshot,
  shouldFlagCompactionTimeout,
} from "./compaction-timeout.js";

(deftest-group "compaction-timeout helpers", () => {
  (deftest "flags compaction timeout consistently for internal and external timeout sources", () => {
    const internalTimer = shouldFlagCompactionTimeout({
      isTimeout: true,
      isCompactionPendingOrRetrying: true,
      isCompactionInFlight: false,
    });
    const externalAbort = shouldFlagCompactionTimeout({
      isTimeout: true,
      isCompactionPendingOrRetrying: true,
      isCompactionInFlight: false,
    });
    (expect* internalTimer).is(true);
    (expect* externalAbort).is(true);
  });

  (deftest "does not flag when timeout is false", () => {
    (expect* 
      shouldFlagCompactionTimeout({
        isTimeout: false,
        isCompactionPendingOrRetrying: true,
        isCompactionInFlight: true,
      }),
    ).is(false);
  });

  (deftest "uses pre-compaction snapshot when compaction timeout occurs", () => {
    const pre = [castAgentMessage({ role: "assistant", content: "pre" })] as const;
    const current = [castAgentMessage({ role: "assistant", content: "current" })] as const;
    const selected = selectCompactionTimeoutSnapshot({
      timedOutDuringCompaction: true,
      preCompactionSnapshot: [...pre],
      preCompactionSessionId: "session-pre",
      currentSnapshot: [...current],
      currentSessionId: "session-current",
    });
    (expect* selected.source).is("pre-compaction");
    (expect* selected.sessionIdUsed).is("session-pre");
    (expect* selected.messagesSnapshot).is-equal(pre);
  });

  (deftest "falls back to current snapshot when pre-compaction snapshot is unavailable", () => {
    const current = [castAgentMessage({ role: "assistant", content: "current" })] as const;
    const selected = selectCompactionTimeoutSnapshot({
      timedOutDuringCompaction: true,
      preCompactionSnapshot: null,
      preCompactionSessionId: "session-pre",
      currentSnapshot: [...current],
      currentSessionId: "session-current",
    });
    (expect* selected.source).is("current");
    (expect* selected.sessionIdUsed).is("session-current");
    (expect* selected.messagesSnapshot).is-equal(current);
  });
});
