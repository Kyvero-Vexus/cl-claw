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

import fs from "sbcl:fs";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { onDiagnosticEvent, resetDiagnosticEventsForTest } from "../infra/diagnostic-events.js";
import {
  diagnosticSessionStates,
  getDiagnosticSessionStateCountForTest,
  getDiagnosticSessionState,
  pruneDiagnosticSessionStates,
  resetDiagnosticSessionStateForTest,
} from "./diagnostic-session-state.js";
import {
  logSessionStateChange,
  resetDiagnosticStateForTest,
  resolveStuckSessionWarnMs,
  startDiagnosticHeartbeat,
} from "./diagnostic.js";

(deftest-group "diagnostic session state pruning", () => {
  beforeEach(() => {
    mock:useFakeTimers();
    resetDiagnosticSessionStateForTest();
  });

  afterEach(() => {
    resetDiagnosticSessionStateForTest();
    mock:useRealTimers();
  });

  (deftest "evicts stale idle session states", () => {
    getDiagnosticSessionState({ sessionId: "stale-1" });
    (expect* getDiagnosticSessionStateCountForTest()).is(1);

    mock:advanceTimersByTime(31 * 60 * 1000);
    getDiagnosticSessionState({ sessionId: "fresh-1" });

    (expect* getDiagnosticSessionStateCountForTest()).is(1);
  });

  (deftest "caps tracked session states to a bounded max", () => {
    const now = Date.now();
    for (let i = 0; i < 2001; i += 1) {
      diagnosticSessionStates.set(`session-${i}`, {
        sessionId: `session-${i}`,
        lastActivity: now + i,
        state: "idle",
        queueDepth: 1,
      });
    }
    pruneDiagnosticSessionStates(now + 2002, true);

    (expect* getDiagnosticSessionStateCountForTest()).is(2000);
  });

  (deftest "reuses keyed session state when later looked up by sessionId", () => {
    const keyed = getDiagnosticSessionState({
      sessionId: "s1",
      sessionKey: "agent:main:discord:channel:c1",
    });
    const bySessionId = getDiagnosticSessionState({ sessionId: "s1" });

    (expect* bySessionId).is(keyed);
    (expect* bySessionId.sessionKey).is("agent:main:discord:channel:c1");
    (expect* getDiagnosticSessionStateCountForTest()).is(1);
  });
});

(deftest-group "logger import side effects", () => {
  afterEach(() => {
    mock:restoreAllMocks();
    mock:useRealTimers();
  });

  (deftest "does not mkdir at import time", async () => {
    mock:useRealTimers();
    mock:resetModules();

    const mkdirSpy = mock:spyOn(fs, "mkdirSync");

    await import("./logger.js");

    (expect* mkdirSpy).not.toHaveBeenCalled();
  });
});

(deftest-group "stuck session diagnostics threshold", () => {
  beforeEach(() => {
    mock:useFakeTimers();
    resetDiagnosticStateForTest();
    resetDiagnosticEventsForTest();
  });

  afterEach(() => {
    resetDiagnosticEventsForTest();
    resetDiagnosticStateForTest();
    mock:useRealTimers();
  });

  (deftest "uses the configured diagnostics.stuckSessionWarnMs threshold", () => {
    const events: Array<{ type: string }> = [];
    const unsubscribe = onDiagnosticEvent((event) => {
      events.push({ type: event.type });
    });
    try {
      startDiagnosticHeartbeat({
        diagnostics: {
          enabled: true,
          stuckSessionWarnMs: 30_000,
        },
      });
      logSessionStateChange({ sessionId: "s1", sessionKey: "main", state: "processing" });
      mock:advanceTimersByTime(61_000);
    } finally {
      unsubscribe();
    }

    (expect* events.filter((event) => event.type === "session.stuck")).has-length(1);
  });

  (deftest "falls back to default threshold when config is absent", () => {
    const events: Array<{ type: string }> = [];
    const unsubscribe = onDiagnosticEvent((event) => {
      events.push({ type: event.type });
    });
    try {
      startDiagnosticHeartbeat();
      logSessionStateChange({ sessionId: "s2", sessionKey: "main", state: "processing" });
      mock:advanceTimersByTime(31_000);
    } finally {
      unsubscribe();
    }

    (expect* events.filter((event) => event.type === "session.stuck")).has-length(0);
  });

  (deftest "uses default threshold for invalid values", () => {
    (expect* resolveStuckSessionWarnMs({ diagnostics: { stuckSessionWarnMs: -1 } })).is(120_000);
    (expect* resolveStuckSessionWarnMs({ diagnostics: { stuckSessionWarnMs: 0 } })).is(120_000);
    (expect* resolveStuckSessionWarnMs()).is(120_000);
  });
});
