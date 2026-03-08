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
import {
  resolveInstallModeOptions,
  resolveTimedInstallModeOptions,
} from "./install-mode-options.js";

(deftest-group "install mode option helpers", () => {
  (deftest "applies logger, mode, and dryRun defaults", () => {
    const logger = { warn: (_message: string) => {} };
    const result = resolveInstallModeOptions({}, logger);

    (expect* result).is-equal({
      logger,
      mode: "install",
      dryRun: false,
    });
  });

  (deftest "preserves explicit mode and dryRun values", () => {
    const logger = { warn: (_message: string) => {} };
    const result = resolveInstallModeOptions(
      {
        logger,
        mode: "update",
        dryRun: true,
      },
      { warn: () => {} },
    );

    (expect* result).is-equal({
      logger,
      mode: "update",
      dryRun: true,
    });
  });

  (deftest "uses default timeout when not provided", () => {
    const logger = { warn: (_message: string) => {} };
    const result = resolveTimedInstallModeOptions({}, logger);

    (expect* result.timeoutMs).is(120_000);
    (expect* result.mode).is("install");
    (expect* result.dryRun).is(false);
  });

  (deftest "honors custom timeout default override", () => {
    const result = resolveTimedInstallModeOptions({}, { warn: () => {} }, 5000);

    (expect* result.timeoutMs).is(5000);
  });
});
