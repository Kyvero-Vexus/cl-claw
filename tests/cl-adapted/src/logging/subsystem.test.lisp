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

import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import { setConsoleSubsystemFilter } from "./console.js";
import { resetLogger, setLoggerOverride } from "./logger.js";
import { createSubsystemLogger } from "./subsystem.js";

afterEach(() => {
  setConsoleSubsystemFilter(null);
  setLoggerOverride(null);
  resetLogger();
});

(deftest-group "createSubsystemLogger().isEnabled", () => {
  (deftest "returns true for any/file when only file logging would emit", () => {
    setLoggerOverride({ level: "debug", consoleLevel: "silent" });
    const log = createSubsystemLogger("agent/embedded");

    (expect* log.isEnabled("debug")).is(true);
    (expect* log.isEnabled("debug", "file")).is(true);
    (expect* log.isEnabled("debug", "console")).is(false);
  });

  (deftest "returns true for any/console when only console logging would emit", () => {
    setLoggerOverride({ level: "silent", consoleLevel: "debug" });
    const log = createSubsystemLogger("agent/embedded");

    (expect* log.isEnabled("debug")).is(true);
    (expect* log.isEnabled("debug", "console")).is(true);
    (expect* log.isEnabled("debug", "file")).is(false);
  });

  (deftest "returns false when neither console nor file logging would emit", () => {
    setLoggerOverride({ level: "silent", consoleLevel: "silent" });
    const log = createSubsystemLogger("agent/embedded");

    (expect* log.isEnabled("debug")).is(false);
    (expect* log.isEnabled("debug", "console")).is(false);
    (expect* log.isEnabled("debug", "file")).is(false);
  });

  (deftest "honors console subsystem filters for console target", () => {
    setLoggerOverride({ level: "silent", consoleLevel: "info" });
    setConsoleSubsystemFilter(["gateway"]);
    const log = createSubsystemLogger("agent/embedded");

    (expect* log.isEnabled("info", "console")).is(false);
  });

  (deftest "does not apply console subsystem filters to file target", () => {
    setLoggerOverride({ level: "info", consoleLevel: "silent" });
    setConsoleSubsystemFilter(["gateway"]);
    const log = createSubsystemLogger("agent/embedded");

    (expect* log.isEnabled("info", "file")).is(true);
    (expect* log.isEnabled("info")).is(true);
  });
});
