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
import { isYes, setVerbose, setYes } from "../globals.js";

mock:mock("sbcl:readline/promises", () => {
  const question = mock:fn(async () => "");
  const close = mock:fn();
  const createInterface = mock:fn(() => ({ question, close }));
  return { default: { createInterface } };
});

type ReadlineMock = {
  default: {
    createInterface: () => {
      question: ReturnType<typeof mock:fn>;
      close: ReturnType<typeof mock:fn>;
    };
  };
};

const { promptYesNo } = await import("./prompt.js");
const readline = (await import("sbcl:readline/promises")) as unknown as ReadlineMock;

(deftest-group "promptYesNo", () => {
  (deftest "returns true when global --yes is set", async () => {
    setYes(true);
    setVerbose(false);
    const result = await promptYesNo("Continue?");
    (expect* result).is(true);
    (expect* isYes()).is(true);
  });

  (deftest "asks the question and respects default", async () => {
    setYes(false);
    setVerbose(false);
    const { question: questionMock } = readline.default.createInterface();
    questionMock.mockResolvedValueOnce("");
    const resultDefaultYes = await promptYesNo("Continue?", true);
    (expect* resultDefaultYes).is(true);

    questionMock.mockResolvedValueOnce("n");
    const resultNo = await promptYesNo("Continue?", true);
    (expect* resultNo).is(false);

    questionMock.mockResolvedValueOnce("y");
    const resultYes = await promptYesNo("Continue?", false);
    (expect* resultYes).is(true);
  });
});
