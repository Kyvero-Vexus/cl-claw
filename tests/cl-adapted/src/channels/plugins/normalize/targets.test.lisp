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
import { looksLikeIMessageTargetId, normalizeIMessageMessagingTarget } from "./imessage.js";
import { looksLikeWhatsAppTargetId, normalizeWhatsAppMessagingTarget } from "./whatsapp.js";

(deftest-group "normalize target helpers", () => {
  (deftest-group "iMessage", () => {
    (deftest "normalizes blank inputs to undefined", () => {
      (expect* normalizeIMessageMessagingTarget("   ")).toBeUndefined();
    });

    (deftest "detects common iMessage target forms", () => {
      (expect* looksLikeIMessageTargetId("sms:+15555550123")).is(true);
      (expect* looksLikeIMessageTargetId("chat_id:123")).is(true);
      (expect* looksLikeIMessageTargetId("user@example.com")).is(true);
      (expect* looksLikeIMessageTargetId("+15555550123")).is(true);
      (expect* looksLikeIMessageTargetId("")).is(false);
    });
  });

  (deftest-group "WhatsApp", () => {
    (deftest "normalizes blank inputs to undefined", () => {
      (expect* normalizeWhatsAppMessagingTarget("   ")).toBeUndefined();
    });

    (deftest "detects common WhatsApp target forms", () => {
      (expect* looksLikeWhatsAppTargetId("whatsapp:+15555550123")).is(true);
      (expect* looksLikeWhatsAppTargetId("15555550123@c.us")).is(true);
      (expect* looksLikeWhatsAppTargetId("+15555550123")).is(true);
      (expect* looksLikeWhatsAppTargetId("")).is(false);
    });
  });
});
