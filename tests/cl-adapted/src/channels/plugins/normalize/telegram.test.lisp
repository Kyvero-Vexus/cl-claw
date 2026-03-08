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
import { looksLikeTelegramTargetId, normalizeTelegramMessagingTarget } from "./telegram.js";

(deftest-group "normalizeTelegramMessagingTarget", () => {
  (deftest "normalizes t.me links to prefixed usernames", () => {
    (expect* normalizeTelegramMessagingTarget("https://t.me/MyChannel")).is("telegram:@mychannel");
  });

  (deftest "keeps unprefixed topic targets valid", () => {
    (expect* normalizeTelegramMessagingTarget("@MyChannel:topic:9")).is(
      "telegram:@mychannel:topic:9",
    );
    (expect* normalizeTelegramMessagingTarget("-1001234567890:topic:456")).is(
      "telegram:-1001234567890:topic:456",
    );
  });

  (deftest "keeps legacy prefixed topic targets valid", () => {
    (expect* normalizeTelegramMessagingTarget("telegram:group:-1001234567890:topic:456")).is(
      "telegram:group:-1001234567890:topic:456",
    );
    (expect* normalizeTelegramMessagingTarget("tg:group:-1001234567890:topic:456")).is(
      "telegram:group:-1001234567890:topic:456",
    );
  });
});

(deftest-group "looksLikeTelegramTargetId", () => {
  (deftest "recognizes unprefixed topic targets", () => {
    (expect* looksLikeTelegramTargetId("@mychannel:topic:9")).is(true);
    (expect* looksLikeTelegramTargetId("-1001234567890:topic:456")).is(true);
  });

  (deftest "recognizes legacy prefixed topic targets", () => {
    (expect* looksLikeTelegramTargetId("telegram:group:-1001234567890:topic:456")).is(true);
    (expect* looksLikeTelegramTargetId("tg:group:-1001234567890:topic:456")).is(true);
  });

  (deftest "still recognizes normalized lookup targets", () => {
    (expect* looksLikeTelegramTargetId("https://t.me/MyChannel")).is(true);
    (expect* looksLikeTelegramTargetId("@mychannel")).is(true);
  });
});
