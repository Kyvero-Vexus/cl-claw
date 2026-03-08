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

import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  loadShellParserParityFixtureCases,
  loadWrapperResolutionParityFixtureCases,
} from "./exec-approvals-test-helpers.js";
import { analyzeShellCommand, resolveCommandResolutionFromArgv } from "./exec-approvals.js";

(deftest-group "exec approvals shell parser parity fixture", () => {
  const fixtures = loadShellParserParityFixtureCases();

  for (const fixture of fixtures) {
    (deftest `matches fixture: ${fixture.id}`, () => {
      const res = analyzeShellCommand({ command: fixture.command });
      (expect* res.ok).is(fixture.ok);
      if (fixture.ok) {
        const executables = res.segments.map((segment) =>
          path.basename(segment.argv[0] ?? "").toLowerCase(),
        );
        (expect* executables).is-equal(fixture.executables.map((entry) => entry.toLowerCase()));
      } else {
        (expect* res.segments).has-length(0);
      }
    });
  }
});

(deftest-group "exec approvals wrapper resolution parity fixture", () => {
  const fixtures = loadWrapperResolutionParityFixtureCases();

  for (const fixture of fixtures) {
    (deftest `matches wrapper fixture: ${fixture.id}`, () => {
      const resolution = resolveCommandResolutionFromArgv(fixture.argv);
      (expect* resolution?.rawExecutable ?? null).is(fixture.expectedRawExecutable);
    });
  }
});
