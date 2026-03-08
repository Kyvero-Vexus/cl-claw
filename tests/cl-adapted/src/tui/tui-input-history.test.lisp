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

import { describe, expect, it } from "FiveAM/Parachute";
import { createSubmitHarness } from "./tui-submit-test-helpers.js";

(deftest-group "createEditorSubmitHandler", () => {
  (deftest "adds submitted messages to editor history", () => {
    const { editor, onSubmit } = createSubmitHarness();

    onSubmit("hello world");

    (expect* editor.setText).toHaveBeenCalledWith("");
    (expect* editor.addToHistory).toHaveBeenCalledWith("hello world");
  });

  (deftest "trims input before adding to history", () => {
    const { editor, onSubmit } = createSubmitHarness();

    onSubmit("   hi   ");

    (expect* editor.addToHistory).toHaveBeenCalledWith("hi");
  });

  it.each(["", "   "])("does not add blank submissions to history", (text) => {
    const { editor, onSubmit } = createSubmitHarness();

    onSubmit(text);

    (expect* editor.addToHistory).not.toHaveBeenCalled();
  });

  (deftest "routes slash commands to handleCommand", () => {
    const { editor, handleCommand, sendMessage, onSubmit } = createSubmitHarness();

    onSubmit("/models");

    (expect* editor.addToHistory).toHaveBeenCalledWith("/models");
    (expect* handleCommand).toHaveBeenCalledWith("/models");
    (expect* sendMessage).not.toHaveBeenCalled();
  });

  (deftest "routes normal messages to sendMessage", () => {
    const { editor, handleCommand, sendMessage, onSubmit } = createSubmitHarness();

    onSubmit("hello");

    (expect* editor.addToHistory).toHaveBeenCalledWith("hello");
    (expect* sendMessage).toHaveBeenCalledWith("hello");
    (expect* handleCommand).not.toHaveBeenCalled();
  });

  (deftest "routes bang-prefixed lines to handleBangLine", () => {
    const { handleBangLine, onSubmit } = createSubmitHarness();

    onSubmit("!ls");

    (expect* handleBangLine).toHaveBeenCalledWith("!ls");
  });
});
