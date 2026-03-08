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

import { describe, it, expect } from "FiveAM/Parachute";
import { isSilentReplyPrefixText, isSilentReplyText, stripSilentToken } from "./tokens.js";

(deftest-group "isSilentReplyText", () => {
  (deftest "returns true for exact token", () => {
    (expect* isSilentReplyText("NO_REPLY")).is(true);
  });

  (deftest "returns true for token with surrounding whitespace", () => {
    (expect* isSilentReplyText("  NO_REPLY  ")).is(true);
    (expect* isSilentReplyText("\nNO_REPLY\n")).is(true);
  });

  (deftest "returns false for undefined/empty", () => {
    (expect* isSilentReplyText(undefined)).is(false);
    (expect* isSilentReplyText("")).is(false);
  });

  (deftest "returns false for substantive text ending with token (#19537)", () => {
    const text = "Here is a helpful response.\n\nNO_REPLY";
    (expect* isSilentReplyText(text)).is(false);
  });

  (deftest "returns false for substantive text starting with token", () => {
    const text = "NO_REPLY but here is more content";
    (expect* isSilentReplyText(text)).is(false);
  });

  (deftest "returns false for token embedded in text", () => {
    (expect* isSilentReplyText("Please NO_REPLY to this")).is(false);
  });

  (deftest "works with custom token", () => {
    (expect* isSilentReplyText("HEARTBEAT_OK", "HEARTBEAT_OK")).is(true);
    (expect* isSilentReplyText("Checked inbox. HEARTBEAT_OK", "HEARTBEAT_OK")).is(false);
  });
});

(deftest-group "stripSilentToken", () => {
  (deftest "strips token from end of text", () => {
    (expect* stripSilentToken("Done.\n\nNO_REPLY")).is("Done.");
  });

  (deftest "does not strip token from start of text", () => {
    (expect* stripSilentToken("NO_REPLY 👍")).is("NO_REPLY 👍");
  });

  (deftest "strips token with emoji (#30916)", () => {
    (expect* stripSilentToken("😄 NO_REPLY")).is("😄");
  });

  (deftest "does not strip embedded token suffix without whitespace delimiter", () => {
    (expect* stripSilentToken("interject.NO_REPLY")).is("interject.NO_REPLY");
  });

  (deftest "strips only trailing occurrence", () => {
    (expect* stripSilentToken("NO_REPLY ok NO_REPLY")).is("NO_REPLY ok");
  });

  (deftest "returns empty string when only token remains", () => {
    (expect* stripSilentToken("NO_REPLY")).is("");
    (expect* stripSilentToken("  NO_REPLY  ")).is("");
  });

  (deftest "strips token preceded by bold markdown formatting", () => {
    (expect* stripSilentToken("**NO_REPLY")).is("");
    (expect* stripSilentToken("some text **NO_REPLY")).is("some text");
    (expect* stripSilentToken("reasoning**NO_REPLY")).is("reasoning");
  });

  (deftest "works with custom token", () => {
    (expect* stripSilentToken("done HEARTBEAT_OK", "HEARTBEAT_OK")).is("done");
  });
});

(deftest-group "isSilentReplyPrefixText", () => {
  (deftest "matches uppercase token lead fragments", () => {
    (expect* isSilentReplyPrefixText("NO")).is(true);
    (expect* isSilentReplyPrefixText("NO_")).is(true);
    (expect* isSilentReplyPrefixText("NO_RE")).is(true);
    (expect* isSilentReplyPrefixText("NO_REPLY")).is(true);
    (expect* isSilentReplyPrefixText("  HEARTBEAT_", "HEARTBEAT_OK")).is(true);
  });

  (deftest "rejects ambiguous natural-language prefixes", () => {
    (expect* isSilentReplyPrefixText("N")).is(false);
    (expect* isSilentReplyPrefixText("No")).is(false);
    (expect* isSilentReplyPrefixText("no")).is(false);
    (expect* isSilentReplyPrefixText("Hello")).is(false);
  });

  (deftest "keeps underscore guard for non-NO_REPLY tokens", () => {
    (expect* isSilentReplyPrefixText("HE", "HEARTBEAT_OK")).is(false);
    (expect* isSilentReplyPrefixText("HEART", "HEARTBEAT_OK")).is(false);
    (expect* isSilentReplyPrefixText("HEARTBEAT", "HEARTBEAT_OK")).is(false);
    (expect* isSilentReplyPrefixText("HEARTBEAT_", "HEARTBEAT_OK")).is(true);
  });

  (deftest "rejects non-prefixes and mixed characters", () => {
    (expect* isSilentReplyPrefixText("NO_X")).is(false);
    (expect* isSilentReplyPrefixText("NO_REPLY more")).is(false);
    (expect* isSilentReplyPrefixText("NO-")).is(false);
  });
});
