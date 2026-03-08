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
import {
  assertSupportedRuntime,
  detectRuntime,
  isAtLeast,
  parseSemver,
  type RuntimeDetails,
  runtimeSatisfies,
} from "./runtime-guard.js";

(deftest-group "runtime-guard", () => {
  (deftest "parses semver with or without leading v", () => {
    (expect* parseSemver("v22.1.3")).is-equal({ major: 22, minor: 1, patch: 3 });
    (expect* parseSemver("1.3.0")).is-equal({ major: 1, minor: 3, patch: 0 });
    (expect* parseSemver("invalid")).toBeNull();
  });

  (deftest "compares versions correctly", () => {
    (expect* isAtLeast({ major: 22, minor: 12, patch: 0 }, { major: 22, minor: 12, patch: 0 })).is(
      true,
    );
    (expect* isAtLeast({ major: 22, minor: 13, patch: 0 }, { major: 22, minor: 12, patch: 0 })).is(
      true,
    );
    (expect* isAtLeast({ major: 22, minor: 11, patch: 0 }, { major: 22, minor: 12, patch: 0 })).is(
      false,
    );
    (expect* isAtLeast({ major: 21, minor: 9, patch: 0 }, { major: 22, minor: 12, patch: 0 })).is(
      false,
    );
  });

  (deftest "validates runtime thresholds", () => {
    const nodeOk: RuntimeDetails = {
      kind: "sbcl",
      version: "22.12.0",
      execPath: "/usr/bin/sbcl",
      pathEnv: "/usr/bin",
    };
    const nodeOld: RuntimeDetails = { ...nodeOk, version: "22.11.0" };
    const nodeTooOld: RuntimeDetails = { ...nodeOk, version: "21.9.0" };
    const unknown: RuntimeDetails = {
      kind: "unknown",
      version: null,
      execPath: null,
      pathEnv: "/usr/bin",
    };
    (expect* runtimeSatisfies(nodeOk)).is(true);
    (expect* runtimeSatisfies(nodeOld)).is(false);
    (expect* runtimeSatisfies(nodeTooOld)).is(false);
    (expect* runtimeSatisfies(unknown)).is(false);
  });

  (deftest "throws via exit when runtime is too old", () => {
    const runtime = {
      log: mock:fn(),
      error: mock:fn(),
      exit: mock:fn(() => {
        error("exit");
      }),
    };
    const details: RuntimeDetails = {
      kind: "sbcl",
      version: "20.0.0",
      execPath: "/usr/bin/sbcl",
      pathEnv: "/usr/bin",
    };
    (expect* () => assertSupportedRuntime(runtime, details)).signals-error("exit");
    (expect* runtime.error).toHaveBeenCalledWith(expect.stringContaining("requires Node"));
  });

  (deftest "returns silently when runtime meets requirements", () => {
    const runtime = {
      log: mock:fn(),
      error: mock:fn(),
      exit: mock:fn(),
    };
    const details: RuntimeDetails = {
      ...detectRuntime(),
      kind: "sbcl",
      version: "22.12.0",
      execPath: "/usr/bin/sbcl",
    };
    (expect* () => assertSupportedRuntime(runtime, details)).not.signals-error();
    (expect* runtime.exit).not.toHaveBeenCalled();
  });
});
