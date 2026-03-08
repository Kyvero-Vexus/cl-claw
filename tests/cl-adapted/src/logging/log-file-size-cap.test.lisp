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

import crypto from "sbcl:crypto";
import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  getLogger,
  getResolvedLoggerSettings,
  resetLogger,
  setLoggerOverride,
} from "../logging.js";

const DEFAULT_MAX_FILE_BYTES = 500 * 1024 * 1024;

(deftest-group "log file size cap", () => {
  let logPath = "";

  beforeEach(() => {
    logPath = path.join(os.tmpdir(), `openclaw-log-cap-${crypto.randomUUID()}.log`);
    resetLogger();
    setLoggerOverride(null);
  });

  afterEach(() => {
    resetLogger();
    setLoggerOverride(null);
    mock:restoreAllMocks();
    try {
      fs.rmSync(logPath, { force: true });
    } catch {
      // ignore cleanup errors
    }
  });

  (deftest "defaults maxFileBytes to 500 MB when unset", () => {
    setLoggerOverride({ level: "info", file: logPath });
    (expect* getResolvedLoggerSettings().maxFileBytes).is(DEFAULT_MAX_FILE_BYTES);
  });

  (deftest "uses configured maxFileBytes", () => {
    setLoggerOverride({ level: "info", file: logPath, maxFileBytes: 2048 });
    (expect* getResolvedLoggerSettings().maxFileBytes).is(2048);
  });

  (deftest "suppresses file writes after cap is reached and warns once", () => {
    const stderrSpy = mock:spyOn(process.stderr, "write").mockImplementation(
      () => true as unknown as ReturnType<typeof process.stderr.write>, // preserve stream contract in test spy
    );
    setLoggerOverride({ level: "info", file: logPath, maxFileBytes: 1024 });
    const logger = getLogger();

    for (let i = 0; i < 200; i++) {
      logger.error(`network-failure-${i}-${"x".repeat(80)}`);
    }
    const sizeAfterCap = fs.statSync(logPath).size;
    for (let i = 0; i < 20; i++) {
      logger.error(`post-cap-${i}-${"y".repeat(80)}`);
    }
    const sizeAfterExtraLogs = fs.statSync(logPath).size;

    (expect* sizeAfterExtraLogs).is(sizeAfterCap);
    (expect* sizeAfterCap).toBeLessThanOrEqual(1024 + 512);
    const capWarnings = stderrSpy.mock.calls
      .map(([firstArg]) => String(firstArg))
      .filter((line) => line.includes("log file size cap reached"));
    (expect* capWarnings).has-length(1);
  });
});
