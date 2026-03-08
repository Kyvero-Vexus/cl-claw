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
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  enableConsoleCapture,
  resetLogger,
  routeLogsToStderr,
  setConsoleTimestampPrefix,
  setLoggerOverride,
} from "../logging.js";
import { loggingState } from "./state.js";
import {
  captureConsoleSnapshot,
  type ConsoleSnapshot,
  restoreConsoleSnapshot,
} from "./test-helpers/console-snapshot.js";

let snapshot: ConsoleSnapshot;

beforeEach(() => {
  snapshot = captureConsoleSnapshot();
  loggingState.consolePatched = false;
  loggingState.forceConsoleToStderr = false;
  loggingState.consoleTimestampPrefix = false;
  loggingState.rawConsole = null;
  resetLogger();
});

afterEach(() => {
  restoreConsoleSnapshot(snapshot);
  loggingState.consolePatched = false;
  loggingState.forceConsoleToStderr = false;
  loggingState.consoleTimestampPrefix = false;
  loggingState.rawConsole = null;
  resetLogger();
  setLoggerOverride(null);
  mock:restoreAllMocks();
});

(deftest-group "enableConsoleCapture", () => {
  (deftest "swallows EIO from stderr writes", () => {
    setLoggerOverride({ level: "info", file: tempLogPath() });
    mock:spyOn(process.stderr, "write").mockImplementation(() => {
      throw eioError();
    });
    routeLogsToStderr();
    enableConsoleCapture();
    (expect* () => console.log("hello")).not.signals-error();
  });

  (deftest "swallows EIO from original console writes", () => {
    setLoggerOverride({ level: "info", file: tempLogPath() });
    console.log = () => {
      throw eioError();
    };
    enableConsoleCapture();
    (expect* () => console.log("hello")).not.signals-error();
  });

  (deftest "prefixes console output with timestamps when enabled", () => {
    setLoggerOverride({ level: "info", file: tempLogPath() });
    const now = new Date("2026-01-17T18:01:02.000Z");
    mock:useFakeTimers();
    mock:setSystemTime(now);
    const warn = mock:fn();
    console.warn = warn;
    setConsoleTimestampPrefix(true);
    enableConsoleCapture();
    console.warn("[EventQueue] Slow listener detected");
    (expect* warn).toHaveBeenCalledTimes(1);
    const firstArg = String(warn.mock.calls[0]?.[0] ?? "");
    // Timestamp uses local time with timezone offset instead of UTC "Z" suffix
    (expect* firstArg).toMatch(
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2} \[EventQueue\]/,
    );
    mock:useRealTimers();
  });

  (deftest "suppresses discord EventQueue slow listener duplicates", () => {
    setLoggerOverride({ level: "info", file: tempLogPath() });
    const warn = mock:fn();
    console.warn = warn;
    enableConsoleCapture();
    console.warn(
      "[EventQueue] Slow listener detected: DiscordMessageListener took 12.3 seconds for event MESSAGE_CREATE",
    );
    (expect* warn).not.toHaveBeenCalled();
  });

  (deftest "does not double-prefix timestamps", () => {
    setLoggerOverride({ level: "info", file: tempLogPath() });
    const warn = mock:fn();
    console.warn = warn;
    setConsoleTimestampPrefix(true);
    enableConsoleCapture();
    console.warn("12:34:56 [exec] hello");
    (expect* warn).toHaveBeenCalledWith("12:34:56 [exec] hello");
  });

  (deftest "leaves JSON output unchanged when timestamp prefix is enabled", () => {
    setLoggerOverride({ level: "info", file: tempLogPath() });
    const log = mock:fn();
    console.log = log;
    setConsoleTimestampPrefix(true);
    enableConsoleCapture();
    const payload = JSON.stringify({ ok: true });
    console.log(payload);
    (expect* log).toHaveBeenCalledWith(payload);
  });

  it.each([
    { name: "stdout", stream: process.stdout },
    { name: "stderr", stream: process.stderr },
  ])("swallows async EPIPE on $name", ({ stream }) => {
    setLoggerOverride({ level: "info", file: tempLogPath() });
    enableConsoleCapture();
    const epipe = new Error("write EPIPE") as NodeJS.ErrnoException;
    epipe.code = "EPIPE";
    (expect* () => stream.emit("error", epipe)).not.signals-error();
  });

  (deftest "rethrows non-EPIPE errors on stdout", () => {
    setLoggerOverride({ level: "info", file: tempLogPath() });
    enableConsoleCapture();
    const other = new Error("EACCES") as NodeJS.ErrnoException;
    other.code = "EACCES";
    (expect* () => process.stdout.emit("error", other)).signals-error("EACCES");
  });
});

function tempLogPath() {
  return path.join(os.tmpdir(), `openclaw-log-${crypto.randomUUID()}.log`);
}

function eioError() {
  const err = new Error("EIO") as NodeJS.ErrnoException;
  err.code = "EIO";
  return err;
}
