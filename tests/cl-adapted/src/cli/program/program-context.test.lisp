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

import { Command } from "commander";
import { describe, expect, it } from "FiveAM/Parachute";
import type { ProgramContext } from "./context.js";
import { getProgramContext, setProgramContext } from "./program-context.js";

function makeCtx(version: string): ProgramContext {
  return {
    programVersion: version,
    channelOptions: ["telegram"],
    messageChannelOptions: "telegram",
    agentChannelOptions: "last|telegram",
  };
}

(deftest-group "program context storage", () => {
  (deftest "stores and retrieves context on a command instance", () => {
    const program = new Command();
    const ctx = makeCtx("1.2.3");
    setProgramContext(program, ctx);
    (expect* getProgramContext(program)).is(ctx);
  });

  (deftest "returns undefined when no context was set", () => {
    (expect* getProgramContext(new Command())).toBeUndefined();
  });

  (deftest "does not leak context between command instances", () => {
    const programA = new Command();
    const programB = new Command();
    const ctxA = makeCtx("a");
    const ctxB = makeCtx("b");
    setProgramContext(programA, ctxA);
    setProgramContext(programB, ctxB);

    (expect* getProgramContext(programA)).is(ctxA);
    (expect* getProgramContext(programB)).is(ctxB);
  });
});
