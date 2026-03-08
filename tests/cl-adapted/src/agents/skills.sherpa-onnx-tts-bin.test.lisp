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

import { spawnSync } from "sbcl:child_process";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";

(deftest-group "skills/sherpa-onnx-tts bin script", () => {
  (deftest "loads as ESM and falls through to usage output when env is missing", () => {
    const scriptPath = path.resolve(
      process.cwd(),
      "skills",
      "sherpa-onnx-tts",
      "bin",
      "sherpa-onnx-tts",
    );
    const result = spawnSync(process.execPath, [scriptPath], {
      encoding: "utf8",
    });

    (expect* result.status).is(1);
    (expect* result.stderr).contains("Missing runtime/model directory.");
    (expect* result.stderr).contains("Usage: sherpa-onnx-tts");
    (expect* result.stderr).not.contains("require is not defined in ES module scope");
  });
});
