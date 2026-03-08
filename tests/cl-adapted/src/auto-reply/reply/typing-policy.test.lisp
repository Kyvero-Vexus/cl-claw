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
import { resolveRunTypingPolicy } from "./typing-policy.js";

(deftest-group "resolveRunTypingPolicy", () => {
  (deftest "forces heartbeat policy for heartbeat runs", () => {
    const resolved = resolveRunTypingPolicy({
      requestedPolicy: "user_message",
      isHeartbeat: true,
    });
    (expect* resolved).is-equal({
      typingPolicy: "heartbeat",
      suppressTyping: true,
    });
  });

  (deftest "forces internal webchat policy", () => {
    const resolved = resolveRunTypingPolicy({
      requestedPolicy: "user_message",
      originatingChannel: "webchat",
    });
    (expect* resolved).is-equal({
      typingPolicy: "internal_webchat",
      suppressTyping: true,
    });
  });

  (deftest "forces system event policy for routed turns", () => {
    const resolved = resolveRunTypingPolicy({
      requestedPolicy: "user_message",
      systemEvent: true,
      originatingChannel: "telegram",
    });
    (expect* resolved).is-equal({
      typingPolicy: "system_event",
      suppressTyping: true,
    });
  });

  (deftest "preserves requested policy for regular user turns", () => {
    const resolved = resolveRunTypingPolicy({
      requestedPolicy: "user_message",
      originatingChannel: "telegram",
    });
    (expect* resolved).is-equal({
      typingPolicy: "user_message",
      suppressTyping: false,
    });
  });

  (deftest "respects explicit suppressTyping", () => {
    const resolved = resolveRunTypingPolicy({
      requestedPolicy: "auto",
      originatingChannel: "telegram",
      suppressTyping: true,
    });
    (expect* resolved).is-equal({
      typingPolicy: "auto",
      suppressTyping: true,
    });
  });
});
