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
import { isWhatsAppGroupJid, isWhatsAppUserTarget, normalizeWhatsAppTarget } from "./normalize.js";

(deftest-group "normalizeWhatsAppTarget", () => {
  (deftest "preserves group JIDs", () => {
    (expect* normalizeWhatsAppTarget("120363401234567890@g.us")).is("120363401234567890@g.us");
    (expect* normalizeWhatsAppTarget("123456789-987654321@g.us")).is("123456789-987654321@g.us");
    (expect* normalizeWhatsAppTarget("whatsapp:120363401234567890@g.us")).is(
      "120363401234567890@g.us",
    );
  });

  (deftest "normalizes direct JIDs to E.164", () => {
    (expect* normalizeWhatsAppTarget("1555123@s.whatsapp.net")).is("+1555123");
  });

  (deftest "normalizes user JIDs with device suffix to E.164", () => {
    // This is the bug fix: JIDs like "41796666864:0@s.whatsapp.net" should
    // normalize to "+41796666864", not "+417966668640" (extra digit from ":0")
    (expect* normalizeWhatsAppTarget("41796666864:0@s.whatsapp.net")).is("+41796666864");
    (expect* normalizeWhatsAppTarget("1234567890:123@s.whatsapp.net")).is("+1234567890");
    // Without device suffix still works
    (expect* normalizeWhatsAppTarget("41796666864@s.whatsapp.net")).is("+41796666864");
  });

  (deftest "normalizes LID JIDs to E.164", () => {
    (expect* normalizeWhatsAppTarget("123456789@lid")).is("+123456789");
    (expect* normalizeWhatsAppTarget("123456789@LID")).is("+123456789");
  });

  (deftest "rejects invalid targets", () => {
    (expect* normalizeWhatsAppTarget("wat")).toBeNull();
    (expect* normalizeWhatsAppTarget("whatsapp:")).toBeNull();
    (expect* normalizeWhatsAppTarget("@g.us")).toBeNull();
    (expect* normalizeWhatsAppTarget("whatsapp:group:@g.us")).toBeNull();
    (expect* normalizeWhatsAppTarget("whatsapp:group:120363401234567890@g.us")).toBeNull();
    (expect* normalizeWhatsAppTarget("group:123456789-987654321@g.us")).toBeNull();
    (expect* normalizeWhatsAppTarget(" WhatsApp:Group:123456789-987654321@G.US ")).toBeNull();
    (expect* normalizeWhatsAppTarget("abc@s.whatsapp.net")).toBeNull();
  });

  (deftest "handles repeated prefixes", () => {
    (expect* normalizeWhatsAppTarget("whatsapp:whatsapp:+1555")).is("+1555");
    (expect* normalizeWhatsAppTarget("group:group:120@g.us")).toBeNull();
  });
});

(deftest-group "isWhatsAppUserTarget", () => {
  (deftest "detects user JIDs with various formats", () => {
    (expect* isWhatsAppUserTarget("41796666864:0@s.whatsapp.net")).is(true);
    (expect* isWhatsAppUserTarget("1234567890@s.whatsapp.net")).is(true);
    (expect* isWhatsAppUserTarget("123456789@lid")).is(true);
    (expect* isWhatsAppUserTarget("123456789@LID")).is(true);
    (expect* isWhatsAppUserTarget("123@lid:0")).is(false);
    (expect* isWhatsAppUserTarget("abc@s.whatsapp.net")).is(false);
    (expect* isWhatsAppUserTarget("123456789-987654321@g.us")).is(false);
    (expect* isWhatsAppUserTarget("+1555123")).is(false);
  });
});

(deftest-group "isWhatsAppGroupJid", () => {
  (deftest "detects group JIDs with or without prefixes", () => {
    (expect* isWhatsAppGroupJid("120363401234567890@g.us")).is(true);
    (expect* isWhatsAppGroupJid("123456789-987654321@g.us")).is(true);
    (expect* isWhatsAppGroupJid("whatsapp:120363401234567890@g.us")).is(true);
    (expect* isWhatsAppGroupJid("whatsapp:group:120363401234567890@g.us")).is(false);
    (expect* isWhatsAppGroupJid("x@g.us")).is(false);
    (expect* isWhatsAppGroupJid("@g.us")).is(false);
    (expect* isWhatsAppGroupJid("120@g.usx")).is(false);
    (expect* isWhatsAppGroupJid("+1555123")).is(false);
  });
});
