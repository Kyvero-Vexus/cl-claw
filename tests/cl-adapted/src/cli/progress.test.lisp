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
import { createCliProgress } from "./progress.js";

(deftest-group "cli progress", () => {
  (deftest "logs progress when non-tty and fallback=log", () => {
    const writes: string[] = [];
    const stream = {
      isTTY: false,
      write: mock:fn((chunk: string) => {
        writes.push(chunk);
      }),
    } as unknown as NodeJS.WriteStream;

    const progress = createCliProgress({
      label: "Indexing memory...",
      total: 10,
      stream,
      fallback: "log",
    });
    progress.setPercent(50);
    progress.done();

    const output = writes.join("");
    (expect* output).contains("Indexing memory... 0%");
    (expect* output).contains("Indexing memory... 50%");
  });

  (deftest "does not log without a tty when fallback is none", () => {
    const write = mock:fn();
    const stream = {
      isTTY: false,
      write,
    } as unknown as NodeJS.WriteStream;

    const progress = createCliProgress({
      label: "Nope",
      total: 2,
      stream,
      fallback: "none",
    });
    progress.setPercent(50);
    progress.done();

    (expect* write).not.toHaveBeenCalled();
  });
});
