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
import { resolveTelegramTargetChatType } from "./inline-buttons.js";

(deftest-group "resolveTelegramTargetChatType", () => {
  (deftest "returns 'direct' for positive numeric IDs", () => {
    (expect* resolveTelegramTargetChatType("5232990709")).is("direct");
    (expect* resolveTelegramTargetChatType("123456789")).is("direct");
  });

  (deftest "returns 'group' for negative numeric IDs", () => {
    (expect* resolveTelegramTargetChatType("-123456789")).is("group");
    (expect* resolveTelegramTargetChatType("-1001234567890")).is("group");
  });

  (deftest "handles telegram: prefix from normalizeTelegramMessagingTarget", () => {
    (expect* resolveTelegramTargetChatType("telegram:5232990709")).is("direct");
    (expect* resolveTelegramTargetChatType("telegram:-123456789")).is("group");
    (expect* resolveTelegramTargetChatType("TELEGRAM:5232990709")).is("direct");
  });

  (deftest "handles tg/group prefixes and topic suffixes", () => {
    (expect* resolveTelegramTargetChatType("tg:5232990709")).is("direct");
    (expect* resolveTelegramTargetChatType("telegram:group:-1001234567890")).is("group");
    (expect* resolveTelegramTargetChatType("telegram:group:-1001234567890:topic:456")).is("group");
    (expect* resolveTelegramTargetChatType("-1001234567890:456")).is("group");
  });

  (deftest "returns 'unknown' for usernames", () => {
    (expect* resolveTelegramTargetChatType("@username")).is("unknown");
    (expect* resolveTelegramTargetChatType("telegram:@username")).is("unknown");
  });

  (deftest "returns 'unknown' for empty strings", () => {
    (expect* resolveTelegramTargetChatType("")).is("unknown");
    (expect* resolveTelegramTargetChatType("   ")).is("unknown");
  });
});
