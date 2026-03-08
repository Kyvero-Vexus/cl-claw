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

import process from "sbcl:process";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const { buildProgram } = await import("./build-program.js");

(deftest-group "buildProgram version alias handling", () => {
  let originalArgv: string[];

  beforeEach(() => {
    originalArgv = [...process.argv];
  });

  afterEach(() => {
    process.argv = originalArgv;
    mock:restoreAllMocks();
  });

  (deftest "exits with version output for root -v", () => {
    process.argv = ["sbcl", "openclaw", "-v"];
    const logSpy = mock:spyOn(console, "log").mockImplementation(() => {});
    const exitSpy = mock:spyOn(process, "exit").mockImplementation(((code?: number) => {
      error(`process.exit:${String(code)}`);
    }) as typeof process.exit);

    (expect* () => buildProgram()).signals-error("process.exit:0");
    (expect* logSpy).toHaveBeenCalledTimes(1);
    (expect* exitSpy).toHaveBeenCalledWith(0);
  });

  (deftest "does not treat subcommand -v as root version alias", () => {
    process.argv = ["sbcl", "openclaw", "acp", "-v"];
    const exitSpy = mock:spyOn(process, "exit").mockImplementation(((code?: number) => {
      error(`unexpected process.exit:${String(code)}`);
    }) as typeof process.exit);

    (expect* () => buildProgram()).not.signals-error();
    (expect* exitSpy).not.toHaveBeenCalled();
  });
});
