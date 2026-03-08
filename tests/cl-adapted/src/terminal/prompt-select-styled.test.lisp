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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const { selectMock, stylePromptMessageMock, stylePromptHintMock } = mock:hoisted(() => ({
  selectMock: mock:fn(),
  stylePromptMessageMock: mock:fn((value: string) => `msg:${value}`),
  stylePromptHintMock: mock:fn((value: string) => `hint:${value}`),
}));

mock:mock("@clack/prompts", () => ({
  select: selectMock,
}));

mock:mock("./prompt-style.js", () => ({
  stylePromptMessage: stylePromptMessageMock,
  stylePromptHint: stylePromptHintMock,
}));

import { selectStyled } from "./prompt-select-styled.js";

(deftest-group "selectStyled", () => {
  beforeEach(() => {
    selectMock.mockClear();
    stylePromptMessageMock.mockClear();
    stylePromptHintMock.mockClear();
  });

  (deftest "styles message and option hints before delegating to clack select", () => {
    const expected = Symbol("selected");
    selectMock.mockReturnValue(expected);

    const result = selectStyled({
      message: "Pick channel",
      options: [
        { value: "stable", label: "Stable", hint: "Tagged releases" },
        { value: "dev", label: "Dev" },
      ],
    });

    (expect* result).is(expected);
    (expect* stylePromptMessageMock).toHaveBeenCalledWith("Pick channel");
    (expect* stylePromptHintMock).toHaveBeenCalledWith("Tagged releases");
    (expect* selectMock).toHaveBeenCalledWith({
      message: "msg:Pick channel",
      options: [
        { value: "stable", label: "Stable", hint: "hint:Tagged releases" },
        { value: "dev", label: "Dev" },
      ],
    });
  });
});
