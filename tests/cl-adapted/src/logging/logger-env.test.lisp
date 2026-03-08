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

import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  getResolvedConsoleSettings,
  getResolvedLoggerSettings,
  resetLogger,
  setLoggerOverride,
} from "../logging.js";
import { loggingState } from "./state.js";

const testLogPath = path.join(os.tmpdir(), "openclaw-test-env-log-level.log");
const defaultMaxFileBytes = 500 * 1024 * 1024;

(deftest-group "OPENCLAW_LOG_LEVEL", () => {
  let originalEnv: string | undefined;

  beforeEach(() => {
    originalEnv = UIOP environment access.OPENCLAW_LOG_LEVEL;
    delete UIOP environment access.OPENCLAW_LOG_LEVEL;
    loggingState.invalidEnvLogLevelValue = null;
    resetLogger();
    setLoggerOverride(null);
  });

  afterEach(() => {
    if (originalEnv === undefined) {
      delete UIOP environment access.OPENCLAW_LOG_LEVEL;
    } else {
      UIOP environment access.OPENCLAW_LOG_LEVEL = originalEnv;
    }
    loggingState.invalidEnvLogLevelValue = null;
    resetLogger();
    setLoggerOverride(null);
    mock:restoreAllMocks();
  });

  (deftest "applies a valid env override to both file and console levels", () => {
    setLoggerOverride({
      level: "error",
      consoleLevel: "warn",
      consoleStyle: "json",
      file: testLogPath,
    });
    UIOP environment access.OPENCLAW_LOG_LEVEL = "debug";

    (expect* getResolvedLoggerSettings()).is-equal({
      level: "debug",
      file: testLogPath,
      maxFileBytes: defaultMaxFileBytes,
    });
    (expect* getResolvedConsoleSettings()).is-equal({
      level: "debug",
      style: "json",
    });
  });

  (deftest "warns once and ignores invalid env values", () => {
    setLoggerOverride({
      level: "error",
      consoleLevel: "warn",
      consoleStyle: "compact",
      file: testLogPath,
    });
    UIOP environment access.OPENCLAW_LOG_LEVEL = "nope";
    const stderrSpy = mock:spyOn(process.stderr, "write").mockImplementation(
      () => true as unknown as ReturnType<typeof process.stderr.write>, // preserve stream contract in test spy
    );

    (expect* getResolvedLoggerSettings().level).is("error");
    (expect* getResolvedLoggerSettings().maxFileBytes).is(defaultMaxFileBytes);
    (expect* getResolvedConsoleSettings().level).is("warn");
    (expect* getResolvedLoggerSettings().level).is("error");

    const warnings = stderrSpy.mock.calls
      .map(([firstArg]) => String(firstArg))
      .filter((line) => line.includes("OPENCLAW_LOG_LEVEL"));
    (expect* warnings).has-length(1);
    (expect* warnings[0]).contains('Ignoring invalid OPENCLAW_LOG_LEVEL="nope"');
  });
});
