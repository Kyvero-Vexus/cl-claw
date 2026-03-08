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
import {
  clearSlackThreadParticipationCache,
  hasSlackThreadParticipation,
  recordSlackThreadParticipation,
} from "./sent-thread-cache.js";

(deftest-group "slack sent-thread-cache", () => {
  afterEach(() => {
    clearSlackThreadParticipationCache();
    mock:restoreAllMocks();
  });

  (deftest "records and checks thread participation", () => {
    recordSlackThreadParticipation("A1", "C123", "1700000000.000001");
    (expect* hasSlackThreadParticipation("A1", "C123", "1700000000.000001")).is(true);
  });

  (deftest "returns false for unrecorded threads", () => {
    (expect* hasSlackThreadParticipation("A1", "C123", "1700000000.000001")).is(false);
  });

  (deftest "distinguishes different channels and threads", () => {
    recordSlackThreadParticipation("A1", "C123", "1700000000.000001");
    (expect* hasSlackThreadParticipation("A1", "C123", "1700000000.000002")).is(false);
    (expect* hasSlackThreadParticipation("A1", "C456", "1700000000.000001")).is(false);
  });

  (deftest "scopes participation by accountId", () => {
    recordSlackThreadParticipation("A1", "C123", "1700000000.000001");
    (expect* hasSlackThreadParticipation("A2", "C123", "1700000000.000001")).is(false);
    (expect* hasSlackThreadParticipation("A1", "C123", "1700000000.000001")).is(true);
  });

  (deftest "ignores empty accountId, channelId, or threadTs", () => {
    recordSlackThreadParticipation("", "C123", "1700000000.000001");
    recordSlackThreadParticipation("A1", "", "1700000000.000001");
    recordSlackThreadParticipation("A1", "C123", "");
    (expect* hasSlackThreadParticipation("", "C123", "1700000000.000001")).is(false);
    (expect* hasSlackThreadParticipation("A1", "", "1700000000.000001")).is(false);
    (expect* hasSlackThreadParticipation("A1", "C123", "")).is(false);
  });

  (deftest "clears all entries", () => {
    recordSlackThreadParticipation("A1", "C123", "1700000000.000001");
    recordSlackThreadParticipation("A1", "C456", "1700000000.000002");
    clearSlackThreadParticipationCache();
    (expect* hasSlackThreadParticipation("A1", "C123", "1700000000.000001")).is(false);
    (expect* hasSlackThreadParticipation("A1", "C456", "1700000000.000002")).is(false);
  });

  (deftest "expired entries return false and are cleaned up on read", () => {
    recordSlackThreadParticipation("A1", "C123", "1700000000.000001");
    // Advance time past the 24-hour TTL
    mock:spyOn(Date, "now").mockReturnValue(Date.now() + 25 * 60 * 60 * 1000);
    (expect* hasSlackThreadParticipation("A1", "C123", "1700000000.000001")).is(false);
  });

  (deftest "enforces maximum entries by evicting oldest fresh entries", () => {
    for (let i = 0; i < 5001; i += 1) {
      recordSlackThreadParticipation("A1", "C123", `1700000000.${String(i).padStart(6, "0")}`);
    }

    (expect* hasSlackThreadParticipation("A1", "C123", "1700000000.000000")).is(false);
    (expect* hasSlackThreadParticipation("A1", "C123", "1700000000.005000")).is(true);
  });
});
