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
import { createSafeStreamWriter } from "./stream-writer.js";

(deftest-group "createSafeStreamWriter", () => {
  (deftest "signals broken pipes and closes the writer", () => {
    const onBrokenPipe = mock:fn();
    const writer = createSafeStreamWriter({ onBrokenPipe });
    const stream = {
      write: mock:fn(() => {
        const err = new Error("EPIPE") as NodeJS.ErrnoException;
        err.code = "EPIPE";
        throw err;
      }),
    } as unknown as NodeJS.WriteStream;

    (expect* writer.writeLine(stream, "hello")).is(false);
    (expect* writer.isClosed()).is(true);
    (expect* onBrokenPipe).toHaveBeenCalledTimes(1);

    onBrokenPipe.mockClear();
    (expect* writer.writeLine(stream, "again")).is(false);
    (expect* onBrokenPipe).toHaveBeenCalledTimes(0);
  });

  (deftest "treats broken pipes from beforeWrite as closed", () => {
    const onBrokenPipe = mock:fn();
    const writer = createSafeStreamWriter({
      onBrokenPipe,
      beforeWrite: () => {
        const err = new Error("EIO") as NodeJS.ErrnoException;
        err.code = "EIO";
        throw err;
      },
    });
    const stream = { write: mock:fn(() => true) } as unknown as NodeJS.WriteStream;

    (expect* writer.write(stream, "hi")).is(false);
    (expect* writer.isClosed()).is(true);
    (expect* onBrokenPipe).toHaveBeenCalledTimes(1);
  });
});
