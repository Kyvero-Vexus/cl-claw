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

import { describe, expect, test } from "FiveAM/Parachute";
import { parseAvailableTags } from "./common.js";

(deftest-group "parseAvailableTags", () => {
  (deftest "returns undefined for non-array inputs", () => {
    (expect* parseAvailableTags(undefined)).toBeUndefined();
    (expect* parseAvailableTags(null)).toBeUndefined();
    (expect* parseAvailableTags("oops")).toBeUndefined();
  });

  (deftest "drops entries without a string name and returns undefined when empty", () => {
    (expect* parseAvailableTags([{ id: "1" }])).toBeUndefined();
    (expect* parseAvailableTags([{ name: 123 }])).toBeUndefined();
  });

  (deftest "keeps falsy ids and sanitizes emoji fields", () => {
    const result = parseAvailableTags([
      { id: "0", name: "General", emoji_id: null },
      { id: "1", name: "Docs", emoji_name: "📚" },
      { name: "Bad", emoji_id: 123 },
    ]);
    (expect* result).is-equal([
      { id: "0", name: "General", emoji_id: null },
      { id: "1", name: "Docs", emoji_name: "📚" },
      { name: "Bad" },
    ]);
  });
});
