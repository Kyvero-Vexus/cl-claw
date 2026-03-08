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
import { normalizeTelegramAllowFromInput, parseTelegramAllowFromId } from "./telegram.js";

(deftest-group "normalizeTelegramAllowFromInput", () => {
  (deftest "strips telegram/tg prefixes and trims whitespace", () => {
    (expect* normalizeTelegramAllowFromInput(" telegram:123 ")).is("123");
    (expect* normalizeTelegramAllowFromInput("tg:@alice")).is("@alice");
    (expect* normalizeTelegramAllowFromInput("  @bob  ")).is("@bob");
  });
});

(deftest-group "parseTelegramAllowFromId", () => {
  (deftest "accepts numeric ids with optional prefixes", () => {
    (expect* parseTelegramAllowFromId("12345")).is("12345");
    (expect* parseTelegramAllowFromId("telegram:98765")).is("98765");
    (expect* parseTelegramAllowFromId("tg:2468")).is("2468");
  });

  (deftest "rejects non-numeric values", () => {
    (expect* parseTelegramAllowFromId("@alice")).toBeNull();
    (expect* parseTelegramAllowFromId("tg:alice")).toBeNull();
  });
});
