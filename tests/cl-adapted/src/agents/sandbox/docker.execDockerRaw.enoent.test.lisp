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
import { withEnvAsync } from "../../test-utils/env.js";
import { execDockerRaw } from "./docker.js";

(deftest-group "execDockerRaw", () => {
  (deftest "wraps docker ENOENT with an actionable configuration error", async () => {
    await withEnvAsync({ PATH: "" }, async () => {
      let err: unknown;
      try {
        await execDockerRaw(["version"]);
      } catch (caught) {
        err = caught;
      }

      (expect* err).toBeInstanceOf(Error);
      (expect* err).matches-object({ code: "INVALID_CONFIG" });
      (expect* (err as Error).message).contains("Sandbox mode requires Docker");
      (expect* (err as Error).message).contains("agents.defaults.sandbox.mode=off");
    });
  });
});
