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
import { listSenderLabelCandidates, resolveSenderLabel } from "./sender-label.js";

(deftest-group "resolveSenderLabel", () => {
  (deftest "prefers display + identifier when both are available", () => {
    (expect* 
      resolveSenderLabel({
        name: " Alice ",
        e164: " +15551234567 ",
      }),
    ).is("Alice (+15551234567)");
  });

  (deftest "falls back to identifier-only labels", () => {
    (expect* 
      resolveSenderLabel({
        id: " user-123 ",
      }),
    ).is("user-123");
  });

  (deftest "returns null when all values are empty", () => {
    (expect* 
      resolveSenderLabel({
        name: " ",
        username: "",
        tag: "   ",
      }),
    ).toBeNull();
  });
});

(deftest-group "listSenderLabelCandidates", () => {
  (deftest "returns unique normalized candidates plus resolved label", () => {
    (expect* 
      listSenderLabelCandidates({
        name: "Alice",
        username: "alice",
        tag: "alice",
        e164: "+15551234567",
        id: "user-123",
      }),
    ).is-equal(["Alice", "alice", "+15551234567", "user-123", "Alice (+15551234567)"]);
  });
});
