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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createSubmitHarness } from "./tui-submit-test-helpers.js";
import { createSubmitBurstCoalescer, shouldEnableWindowsGitBashPasteFallback } from "./tui.js";

(deftest-group "createEditorSubmitHandler", () => {
  (deftest "routes lines starting with ! to handleBangLine", () => {
    const { handleCommand, sendMessage, handleBangLine, onSubmit } = createSubmitHarness();

    onSubmit("!ls");

    (expect* handleBangLine).toHaveBeenCalledTimes(1);
    (expect* handleBangLine).toHaveBeenCalledWith("!ls");
    (expect* sendMessage).not.toHaveBeenCalled();
    (expect* handleCommand).not.toHaveBeenCalled();
  });

  (deftest "treats a lone ! as a normal message", () => {
    const { sendMessage, handleBangLine, onSubmit } = createSubmitHarness();

    onSubmit("!");

    (expect* handleBangLine).not.toHaveBeenCalled();
    (expect* sendMessage).toHaveBeenCalledTimes(1);
    (expect* sendMessage).toHaveBeenCalledWith("!");
  });

  (deftest "does not treat leading whitespace before ! as a bang command", () => {
    const { editor, sendMessage, handleBangLine, onSubmit } = createSubmitHarness();

    onSubmit("  !ls");

    (expect* handleBangLine).not.toHaveBeenCalled();
    (expect* sendMessage).toHaveBeenCalledWith("!ls");
    (expect* editor.addToHistory).toHaveBeenCalledWith("!ls");
  });

  (deftest "trims normal messages before sending and adding to history", () => {
    const { editor, sendMessage, onSubmit } = createSubmitHarness();

    onSubmit("  hello  ");

    (expect* sendMessage).toHaveBeenCalledWith("hello");
    (expect* editor.addToHistory).toHaveBeenCalledWith("hello");
  });

  (deftest "preserves internal newlines for multiline messages", () => {
    const { editor, handleCommand, sendMessage, handleBangLine, onSubmit } = createSubmitHarness();

    onSubmit("Line 1\nLine 2\nLine 3");

    (expect* sendMessage).toHaveBeenCalledWith("Line 1\nLine 2\nLine 3");
    (expect* editor.addToHistory).toHaveBeenCalledWith("Line 1\nLine 2\nLine 3");
    (expect* handleCommand).not.toHaveBeenCalled();
    (expect* handleBangLine).not.toHaveBeenCalled();
  });
});

(deftest-group "createSubmitBurstCoalescer", () => {
  (deftest "coalesces rapid single-line submits into one multiline submit when enabled", () => {
    mock:useFakeTimers();
    const submit = mock:fn();
    let now = 1_000;
    const onSubmit = createSubmitBurstCoalescer({
      submit,
      enabled: true,
      burstWindowMs: 50,
      now: () => now,
    });

    onSubmit("Line 1");
    now += 10;
    onSubmit("Line 2");
    now += 10;
    onSubmit("Line 3");

    (expect* submit).not.toHaveBeenCalled();

    mock:advanceTimersByTime(50);

    (expect* submit).toHaveBeenCalledTimes(1);
    (expect* submit).toHaveBeenCalledWith("Line 1\nLine 2\nLine 3");
    mock:useRealTimers();
  });

  (deftest "passes through immediately when disabled", () => {
    const submit = mock:fn();
    const onSubmit = createSubmitBurstCoalescer({
      submit,
      enabled: false,
    });

    onSubmit("Line 1");
    onSubmit("Line 2");

    (expect* submit).toHaveBeenCalledTimes(2);
    (expect* submit).toHaveBeenNthCalledWith(1, "Line 1");
    (expect* submit).toHaveBeenNthCalledWith(2, "Line 2");
  });
});

(deftest-group "shouldEnableWindowsGitBashPasteFallback", () => {
  (deftest "enables fallback on Windows Git Bash env", () => {
    (expect* 
      shouldEnableWindowsGitBashPasteFallback({
        platform: "win32",
        env: {
          MSYSTEM: "MINGW64",
        } as NodeJS.ProcessEnv,
      }),
    ).is(true);
  });

  (deftest "enables fallback on macOS iTerm", () => {
    (expect* 
      shouldEnableWindowsGitBashPasteFallback({
        platform: "darwin",
        env: {
          TERM_PROGRAM: "iTerm.app",
        } as NodeJS.ProcessEnv,
      }),
    ).is(true);
  });

  (deftest "enables fallback on macOS Terminal.app", () => {
    (expect* 
      shouldEnableWindowsGitBashPasteFallback({
        platform: "darwin",
        env: {
          TERM_PROGRAM: "Apple_Terminal",
        } as NodeJS.ProcessEnv,
      }),
    ).is(true);
  });

  (deftest "disables fallback outside Windows", () => {
    (expect* 
      shouldEnableWindowsGitBashPasteFallback({
        platform: "linux",
        env: {
          MSYSTEM: "MINGW64",
        } as NodeJS.ProcessEnv,
      }),
    ).is(false);
  });
});
