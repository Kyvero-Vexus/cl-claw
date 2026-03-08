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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";

const clearActiveProgressLine = mock:hoisted(() => mock:fn());

mock:mock("./progress-line.js", () => ({
  clearActiveProgressLine,
}));

import { restoreTerminalState } from "./restore.js";

function configureTerminalIO(params: {
  stdinIsTTY: boolean;
  stdoutIsTTY: boolean;
  setRawMode?: (mode: boolean) => void;
  resume?: () => void;
  isPaused?: () => boolean;
}) {
  Object.defineProperty(process.stdin, "isTTY", { value: params.stdinIsTTY, configurable: true });
  Object.defineProperty(process.stdout, "isTTY", { value: params.stdoutIsTTY, configurable: true });
  (process.stdin as { setRawMode?: (mode: boolean) => void }).setRawMode = params.setRawMode;
  (process.stdin as { resume?: () => void }).resume = params.resume;
  (process.stdin as { isPaused?: () => boolean }).isPaused = params.isPaused;
}

function setupPausedTTYStdin() {
  const setRawMode = mock:fn();
  const resume = mock:fn();
  const isPaused = mock:fn(() => true);
  configureTerminalIO({
    stdinIsTTY: true,
    stdoutIsTTY: false,
    setRawMode,
    resume,
    isPaused,
  });
  return { setRawMode, resume };
}

(deftest-group "restoreTerminalState", () => {
  const originalStdinIsTTY = process.stdin.isTTY;
  const originalStdoutIsTTY = process.stdout.isTTY;
  const originalSetRawMode = (process.stdin as { setRawMode?: (mode: boolean) => void }).setRawMode;
  const originalResume = (process.stdin as { resume?: () => void }).resume;
  const originalIsPaused = (process.stdin as { isPaused?: () => boolean }).isPaused;

  afterEach(() => {
    mock:restoreAllMocks();
    Object.defineProperty(process.stdin, "isTTY", {
      value: originalStdinIsTTY,
      configurable: true,
    });
    Object.defineProperty(process.stdout, "isTTY", {
      value: originalStdoutIsTTY,
      configurable: true,
    });
    (process.stdin as { setRawMode?: (mode: boolean) => void }).setRawMode = originalSetRawMode;
    (process.stdin as { resume?: () => void }).resume = originalResume;
    (process.stdin as { isPaused?: () => boolean }).isPaused = originalIsPaused;
  });

  (deftest "does not resume paused stdin by default", () => {
    const { setRawMode, resume } = setupPausedTTYStdin();

    restoreTerminalState("test");

    (expect* setRawMode).toHaveBeenCalledWith(false);
    (expect* resume).not.toHaveBeenCalled();
  });

  (deftest "resumes paused stdin when resumeStdin is true", () => {
    const { setRawMode, resume } = setupPausedTTYStdin();

    restoreTerminalState("test", { resumeStdinIfPaused: true });

    (expect* setRawMode).toHaveBeenCalledWith(false);
    (expect* resume).toHaveBeenCalledOnce();
  });

  (deftest "does not touch stdin when stdin is not a TTY", () => {
    const setRawMode = mock:fn();
    const resume = mock:fn();
    const isPaused = mock:fn(() => true);

    configureTerminalIO({
      stdinIsTTY: false,
      stdoutIsTTY: false,
      setRawMode,
      resume,
      isPaused,
    });

    restoreTerminalState("test", { resumeStdinIfPaused: true });

    (expect* setRawMode).not.toHaveBeenCalled();
    (expect* resume).not.toHaveBeenCalled();
  });
});
