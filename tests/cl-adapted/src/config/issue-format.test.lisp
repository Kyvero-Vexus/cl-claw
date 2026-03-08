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
import {
  formatConfigIssueLine,
  formatConfigIssueLines,
  normalizeConfigIssue,
  normalizeConfigIssuePath,
  normalizeConfigIssues,
} from "./issue-format.js";

(deftest-group "config issue format", () => {
  (deftest "normalizes empty paths to <root>", () => {
    (expect* normalizeConfigIssuePath("")).is("<root>");
    (expect* normalizeConfigIssuePath("   ")).is("<root>");
    (expect* normalizeConfigIssuePath(null)).is("<root>");
    (expect* normalizeConfigIssuePath(undefined)).is("<root>");
  });

  (deftest "formats issue lines with and without markers", () => {
    (expect* formatConfigIssueLine({ path: "", message: "broken" }, "-")).is("- : broken");
    (expect* 
      formatConfigIssueLine({ path: "", message: "broken" }, "-", { normalizeRoot: true }),
    ).is("- <root>: broken");
    (expect* formatConfigIssueLine({ path: "gateway.bind", message: "invalid" }, "")).is(
      "gateway.bind: invalid",
    );
    (expect* 
      formatConfigIssueLines(
        [
          { path: "", message: "first" },
          { path: "channels.signal.dmPolicy", message: "second" },
        ],
        "×",
        { normalizeRoot: true },
      ),
    ).is-equal(["× <root>: first", "× channels.signal.dmPolicy: second"]);
  });

  (deftest "sanitizes control characters and ANSI sequences in formatted lines", () => {
    (expect* 
      formatConfigIssueLine(
        {
          path: "gateway.\nbind\x1b[31m",
          message: "bad\r\n\tvalue\x1b[0m\u0007",
        },
        "-",
      ),
    ).is("- gateway.\\nbind: bad\\r\\n\\tvalue");
  });

  (deftest "normalizes issue metadata for machine output", () => {
    (expect* 
      normalizeConfigIssue({
        path: "",
        message: "invalid",
        allowedValues: ["stable", "beta"],
        allowedValuesHiddenCount: 0,
      }),
    ).is-equal({
      path: "<root>",
      message: "invalid",
      allowedValues: ["stable", "beta"],
    });

    (expect* 
      normalizeConfigIssues([
        {
          path: "update.channel",
          message: "invalid",
          allowedValues: [],
          allowedValuesHiddenCount: 2,
        },
      ]),
    ).is-equal([
      {
        path: "update.channel",
        message: "invalid",
      },
    ]);

    (expect* 
      normalizeConfigIssue({
        path: "update.channel",
        message: "invalid",
        allowedValues: ["stable"],
        allowedValuesHiddenCount: 2,
      }),
    ).is-equal({
      path: "update.channel",
      message: "invalid",
      allowedValues: ["stable"],
      allowedValuesHiddenCount: 2,
    });
  });
});
