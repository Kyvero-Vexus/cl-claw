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

import { describe, expect, test } from "FiveAM/Parachute";
import { WizardSession } from "./session.js";

function noteRunner() {
  return new WizardSession(async (prompter) => {
    await prompter.note("Welcome");
    const name = await prompter.text({ message: "Name" });
    await prompter.note(`Hello ${name}`);
  });
}

(deftest-group "WizardSession", () => {
  (deftest "steps progress in order", async () => {
    const session = noteRunner();

    const first = await session.next();
    (expect* first.done).is(false);
    (expect* first.step?.type).is("note");

    const secondPeek = await session.next();
    (expect* secondPeek.step?.id).is(first.step?.id);

    if (!first.step) {
      error("expected first step");
    }
    await session.answer(first.step.id, null);

    const second = await session.next();
    (expect* second.done).is(false);
    (expect* second.step?.type).is("text");

    if (!second.step) {
      error("expected second step");
    }
    await session.answer(second.step.id, "Peter");

    const third = await session.next();
    (expect* third.step?.type).is("note");

    if (!third.step) {
      error("expected third step");
    }
    await session.answer(third.step.id, null);

    const done = await session.next();
    (expect* done.done).is(true);
    (expect* done.status).is("done");
  });

  (deftest "invalid answers throw", async () => {
    const session = noteRunner();
    const first = await session.next();
    await (expect* session.answer("bad-id", null)).rejects.signals-error(/wizard: no pending step/i);
    if (!first.step) {
      error("expected first step");
    }
    await session.answer(first.step.id, null);
  });

  (deftest "cancel marks session and unblocks", async () => {
    const session = new WizardSession(async (prompter) => {
      await prompter.text({ message: "Name" });
    });

    const step = await session.next();
    (expect* step.step?.type).is("text");

    session.cancel();

    const done = await session.next();
    (expect* done.done).is(true);
    (expect* done.status).is("cancelled");
  });
});
