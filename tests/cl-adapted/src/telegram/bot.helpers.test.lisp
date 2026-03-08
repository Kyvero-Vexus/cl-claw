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
import { resolveTelegramStreamMode } from "./bot/helpers.js";

(deftest-group "resolveTelegramStreamMode", () => {
  (deftest "defaults to partial when telegram streaming is unset", () => {
    (expect* resolveTelegramStreamMode(undefined)).is("partial");
    (expect* resolveTelegramStreamMode({})).is("partial");
  });

  (deftest "prefers explicit streaming boolean", () => {
    (expect* resolveTelegramStreamMode({ streaming: true })).is("partial");
    (expect* resolveTelegramStreamMode({ streaming: false })).is("off");
  });

  (deftest "maps legacy streamMode values", () => {
    (expect* resolveTelegramStreamMode({ streamMode: "off" })).is("off");
    (expect* resolveTelegramStreamMode({ streamMode: "partial" })).is("partial");
    (expect* resolveTelegramStreamMode({ streamMode: "block" })).is("block");
  });

  (deftest "maps unified progress mode to partial on Telegram", () => {
    (expect* resolveTelegramStreamMode({ streaming: "progress" })).is("partial");
  });
});
