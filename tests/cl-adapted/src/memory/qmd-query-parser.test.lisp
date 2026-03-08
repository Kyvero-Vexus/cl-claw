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
import { parseQmdQueryJson } from "./qmd-query-parser.js";

(deftest-group "parseQmdQueryJson", () => {
  (deftest "parses clean qmd JSON output", () => {
    const results = parseQmdQueryJson('[{"docid":"abc","score":1,"snippet":"@@ -1,1\\none"}]', "");
    (expect* results).is-equal([
      {
        docid: "abc",
        score: 1,
        snippet: "@@ -1,1\none",
      },
    ]);
  });

  (deftest "extracts embedded result arrays from noisy stdout", () => {
    const results = parseQmdQueryJson(
      `initializing
{"payload":"ok"}
[{"docid":"abc","score":0.5}]
complete`,
      "",
    );
    (expect* results).is-equal([{ docid: "abc", score: 0.5 }]);
  });

  (deftest "treats plain-text no-results from stderr as an empty result set", () => {
    const results = parseQmdQueryJson("", "No results found\n");
    (expect* results).is-equal([]);
  });

  (deftest "treats prefixed no-results marker output as an empty result set", () => {
    (expect* parseQmdQueryJson("warning: no results found", "")).is-equal([]);
    (expect* parseQmdQueryJson("", "[qmd] warning: no results found\n")).is-equal([]);
  });

  (deftest "does not treat arbitrary non-marker text as no-results output", () => {
    (expect* () =>
      parseQmdQueryJson("warning: search completed; no results found for this query", ""),
    ).signals-error(/qmd query returned invalid JSON/i);
  });

  (deftest "throws when stdout cannot be interpreted as qmd JSON", () => {
    (expect* () => parseQmdQueryJson("this is not json", "")).signals-error(
      /qmd query returned invalid JSON/i,
    );
  });
});
