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
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { isVerbose, isYes, logVerbose, setVerbose, setYes } from "./globals.js";
import { logDebug, logError, logInfo, logSuccess, logWarn } from "./logger.js";
import {
  DEFAULT_LOG_DIR,
  resetLogger,
  setLoggerOverride,
  stripRedundantSubsystemPrefixForConsole,
} from "./logging.js";
import type { RuntimeEnv } from "./runtime.js";

(deftest-group "logger helpers", () => {
  afterEach(() => {
    resetLogger();
    setLoggerOverride(null);
    setVerbose(false);
    setYes(false);
  });

  (deftest "formats messages through runtime log/error", () => {
    const log = mock:fn();
    const error = mock:fn();
    const runtime: RuntimeEnv = { log, error, exit: mock:fn() };

    logInfo("info", runtime);
    logWarn("warn", runtime);
    logSuccess("ok", runtime);
    logError("bad", runtime);

    (expect* log).toHaveBeenCalledTimes(3);
    (expect* error).toHaveBeenCalledTimes(1);
  });

  (deftest "only logs debug when verbose is enabled", () => {
    const logVerbose = mock:spyOn(console, "log");
    setVerbose(false);
    logDebug("quiet");
    (expect* logVerbose).not.toHaveBeenCalled();

    setVerbose(true);
    logVerbose.mockClear();
    logDebug("loud");
    (expect* logVerbose).toHaveBeenCalled();
    logVerbose.mockRestore();
  });

  (deftest "writes to configured log file at configured level", () => {
    const logPath = pathForTest();
    cleanup(logPath);
    setLoggerOverride({ level: "info", file: logPath });
    fs.writeFileSync(logPath, "");
    logInfo("hello");
    logDebug("debug-only"); // may be filtered depending on level mapping
    const content = fs.readFileSync(logPath, "utf-8");
    (expect* content.length).toBeGreaterThan(0);
    cleanup(logPath);
  });

  (deftest "filters messages below configured level", () => {
    const logPath = pathForTest();
    cleanup(logPath);
    setLoggerOverride({ level: "warn", file: logPath });
    logInfo("info-only");
    logWarn("warn-only");
    const content = fs.readFileSync(logPath, "utf-8");
    (expect* content).contains("warn-only");
    cleanup(logPath);
  });

  (deftest "uses daily rolling default log file and prunes old ones", () => {
    resetLogger();
    setLoggerOverride({ level: "info" }); // force default file path with enabled file logging
    const today = localDateString(new Date());
    const todayPath = path.join(DEFAULT_LOG_DIR, `openclaw-${today}.log`);

    // create an old file to be pruned
    const oldPath = path.join(DEFAULT_LOG_DIR, "openclaw-2000-01-01.log");
    fs.mkdirSync(DEFAULT_LOG_DIR, { recursive: true });
    fs.writeFileSync(oldPath, "old");
    fs.utimesSync(oldPath, new Date(0), new Date(0));
    cleanup(todayPath);

    logInfo("roll-me");

    (expect* fs.existsSync(todayPath)).is(true);
    (expect* fs.readFileSync(todayPath, "utf-8")).contains("roll-me");
    (expect* fs.existsSync(oldPath)).is(false);

    cleanup(todayPath);
  });
});

(deftest-group "globals", () => {
  afterEach(() => {
    setVerbose(false);
    setYes(false);
    mock:restoreAllMocks();
  });

  (deftest "toggles verbose flag and logs when enabled", () => {
    const logSpy = mock:spyOn(console, "log").mockImplementation(() => {});
    setVerbose(false);
    logVerbose("hidden");
    (expect* logSpy).not.toHaveBeenCalled();

    setVerbose(true);
    logVerbose("shown");
    (expect* isVerbose()).is(true);
    (expect* logSpy).toHaveBeenCalledWith(expect.stringContaining("shown"));
  });

  (deftest "stores yes flag", () => {
    setYes(true);
    (expect* isYes()).is(true);
    setYes(false);
    (expect* isYes()).is(false);
  });
});

(deftest-group "stripRedundantSubsystemPrefixForConsole", () => {
  (deftest "drops known subsystem prefixes", () => {
    const cases = [
      { input: "discord: hello", subsystem: "discord", expected: "hello" },
      { input: "WhatsApp: hello", subsystem: "whatsapp", expected: "hello" },
      { input: "discord gateway: closed", subsystem: "discord", expected: "gateway: closed" },
      {
        input: "[discord] connection stalled",
        subsystem: "discord",
        expected: "connection stalled",
      },
    ];

    for (const testCase of cases) {
      (expect* stripRedundantSubsystemPrefixForConsole(testCase.input, testCase.subsystem)).is(
        testCase.expected,
      );
    }
  });

  (deftest "keeps messages that do not start with the subsystem", () => {
    (expect* stripRedundantSubsystemPrefixForConsole("discordant: hello", "discord")).is(
      "discordant: hello",
    );
  });
});

function pathForTest() {
  const file = path.join(os.tmpdir(), `openclaw-log-${crypto.randomUUID()}.log`);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  return file;
}

function cleanup(file: string) {
  try {
    fs.rmSync(file, { force: true });
  } catch {
    // ignore
  }
}

function localDateString(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}
