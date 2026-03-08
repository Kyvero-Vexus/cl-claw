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
import { markdownToSignalText } from "./format.js";

(deftest-group "markdownToSignalText", () => {
  (deftest-group "duplicate URL display", () => {
    (deftest "does not duplicate URL for normalized equivalent labels", () => {
      const equivalentCases = [
        { input: "[selfh.st](http://selfh.st)", expected: "selfh.st" },
        { input: "[example.com](https://example.com)", expected: "example.com" },
        { input: "[www.example.com](https://example.com)", expected: "www.example.com" },
        { input: "[example.com](https://example.com/)", expected: "example.com" },
        { input: "[example.com](https://example.com///)", expected: "example.com" },
        { input: "[example.com](https://www.example.com)", expected: "example.com" },
        { input: "[EXAMPLE.COM](https://example.com)", expected: "EXAMPLE.COM" },
        { input: "[example.com/page](https://example.com/page)", expected: "example.com/page" },
      ] as const;

      for (const { input, expected } of equivalentCases) {
        const res = markdownToSignalText(input);
        (expect* res.text).is(expected);
      }
    });

    (deftest "still shows URL when label is meaningfully different", () => {
      const res = markdownToSignalText("[click here](https://example.com)");
      (expect* res.text).is("click here (https://example.com)");
    });

    (deftest "handles URL with path - should show URL when label is just domain", () => {
      // Label is just domain, URL has path - these are meaningfully different
      const res = markdownToSignalText("[example.com](https://example.com/page)");
      (expect* res.text).is("example.com (https://example.com/page)");
    });
  });
});
