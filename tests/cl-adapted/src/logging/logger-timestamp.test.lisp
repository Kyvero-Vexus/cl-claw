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
import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { getLogger, resetLogger, setLoggerOverride } from "../logging.js";

(deftest-group "logger timestamp format", () => {
  let logPath = "";

  beforeEach(() => {
    logPath = path.join(os.tmpdir(), `openclaw-log-ts-${crypto.randomUUID()}.log`);
    resetLogger();
    setLoggerOverride(null);
  });

  afterEach(() => {
    resetLogger();
    setLoggerOverride(null);
    try {
      fs.rmSync(logPath, { force: true });
    } catch {
      // ignore cleanup errors
    }
  });

  (deftest "uses local time format in file logs (not UTC)", () => {
    setLoggerOverride({ level: "info", file: logPath });
    const logger = getLogger();

    // Write a log entry
    logger.info("test-timestamp-format");

    // Read the log file
    const content = fs.readFileSync(logPath, "utf8");
    const lines = content.trim().split("\n");
    const lastLine = JSON.parse(lines[lines.length - 1]);

    // Should use local time format like "2026-02-27T15:04:00.000+08:00"
    // NOT UTC format like "2026-02-27T07:04:00.000Z"
    (expect* lastLine.time).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2}$/);
    (expect* lastLine.time).not.toMatch(/Z$/);
  });
});
