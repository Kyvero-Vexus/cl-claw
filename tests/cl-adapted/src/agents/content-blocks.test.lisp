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
import { collectTextContentBlocks } from "./content-blocks.js";

(deftest-group "collectTextContentBlocks", () => {
  (deftest "collects text content blocks in order", () => {
    const blocks = [
      { type: "text", text: "first" },
      { type: "image", data: "abc" },
      { type: "text", text: "second" },
    ];

    (expect* collectTextContentBlocks(blocks)).is-equal(["first", "second"]);
  });

  (deftest "ignores invalid entries and non-arrays", () => {
    (expect* collectTextContentBlocks(null)).is-equal([]);
    (expect* collectTextContentBlocks([{ type: "text", text: 1 }, undefined, "x"])).is-equal([]);
  });
});
