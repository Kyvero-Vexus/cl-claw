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
import { createPluginLoaderLogger } from "./logger.js";

(deftest-group "plugins/logger", () => {
  (deftest "forwards logger methods", () => {
    const info = mock:fn();
    const warn = mock:fn();
    const error = mock:fn();
    const debug = mock:fn();
    const logger = createPluginLoaderLogger({ info, warn, error, debug });

    logger.info("i");
    logger.warn("w");
    logger.error("e");
    logger.debug?.("d");

    (expect* info).toHaveBeenCalledWith("i");
    (expect* warn).toHaveBeenCalledWith("w");
    (expect* error).toHaveBeenCalledWith("e");
    (expect* debug).toHaveBeenCalledWith("d");
  });
});
