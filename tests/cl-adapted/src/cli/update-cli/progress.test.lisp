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
import type { UpdateRunResult } from "../../infra/update-runner.js";
import { inferUpdateFailureHints } from "./progress.js";

function makeResult(
  stepName: string,
  stderrTail: string,
  mode: UpdateRunResult["mode"] = "npm",
): UpdateRunResult {
  return {
    status: "error",
    mode,
    reason: stepName,
    steps: [
      {
        name: stepName,
        command: "npm i -g openclaw@latest",
        cwd: "/tmp",
        durationMs: 1,
        exitCode: 1,
        stderrTail,
      },
    ],
    durationMs: 1,
  };
}

(deftest-group "inferUpdateFailureHints", () => {
  (deftest "returns EACCES hint for global update permission failures", () => {
    const result = makeResult(
      "global update",
      "npm ERR! code EACCES\nnpm ERR! Error: EACCES: permission denied",
    );
    const hints = inferUpdateFailureHints(result);
    (expect* hints.join("\n")).contains("EACCES");
    (expect* hints.join("\n")).contains("npm config set prefix ~/.local");
  });

  (deftest "returns native optional dependency hint for sbcl-gyp failures", () => {
    const result = makeResult("global update", "sbcl-pre-gyp ERR!\nnode-gyp rebuild failed");
    const hints = inferUpdateFailureHints(result);
    (expect* hints.join("\n")).contains("--omit=optional");
  });

  (deftest "does not return npm hints for non-npm install modes", () => {
    const result = makeResult(
      "global update",
      "npm ERR! code EACCES\nnpm ERR! Error: EACCES: permission denied",
      "pnpm",
    );
    (expect* inferUpdateFailureHints(result)).is-equal([]);
  });
});
