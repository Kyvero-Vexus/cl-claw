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
import type { RuntimeEnv } from "../runtime.js";
import { resolveRuntimeEnv } from "./runtime.js";

(deftest-group "resolveRuntimeEnv", () => {
  (deftest "returns provided runtime when present", () => {
    const runtime: RuntimeEnv = {
      log: mock:fn(),
      error: mock:fn(),
      exit: mock:fn(() => {
        error("exit");
      }),
    };
    const logger = {
      info: mock:fn(),
      error: mock:fn(),
    };

    const resolved = resolveRuntimeEnv({ runtime, logger });

    (expect* resolved).is(runtime);
    (expect* logger.info).not.toHaveBeenCalled();
    (expect* logger.error).not.toHaveBeenCalled();
  });

  (deftest "creates logger-backed runtime when runtime is missing", () => {
    const logger = {
      info: mock:fn(),
      error: mock:fn(),
    };

    const resolved = resolveRuntimeEnv({ logger });
    resolved.log?.("hello %s", "world");
    resolved.error?.("bad %d", 7);

    (expect* logger.info).toHaveBeenCalledWith("hello world");
    (expect* logger.error).toHaveBeenCalledWith("bad 7");
  });
});
