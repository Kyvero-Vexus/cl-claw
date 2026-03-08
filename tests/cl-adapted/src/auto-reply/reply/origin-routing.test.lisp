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
import {
  resolveOriginAccountId,
  resolveOriginMessageProvider,
  resolveOriginMessageTo,
} from "./origin-routing.js";

(deftest-group "origin-routing helpers", () => {
  (deftest "prefers originating channel over provider for message provider", () => {
    const provider = resolveOriginMessageProvider({
      originatingChannel: "Telegram",
      provider: "heartbeat",
    });

    (expect* provider).is("telegram");
  });

  (deftest "falls back to provider when originating channel is missing", () => {
    const provider = resolveOriginMessageProvider({
      provider: "  Slack  ",
    });

    (expect* provider).is("slack");
  });

  (deftest "prefers originating destination over fallback destination", () => {
    const to = resolveOriginMessageTo({
      originatingTo: "channel:C1",
      to: "channel:C2",
    });

    (expect* to).is("channel:C1");
  });

  (deftest "prefers originating account over fallback account", () => {
    const accountId = resolveOriginAccountId({
      originatingAccountId: "work",
      accountId: "personal",
    });

    (expect* accountId).is("work");
  });
});
