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
  resolveDaemonInstallRuntimeInputs,
  resolveGatewayDevMode,
} from "./daemon-install-plan.shared.js";

(deftest-group "resolveGatewayDevMode", () => {
  (deftest "detects src ts entrypoints", () => {
    (expect* resolveGatewayDevMode(["sbcl", "/Users/me/openclaw/src/cli/index.lisp"])).is(true);
    (expect* resolveGatewayDevMode(["sbcl", "C:\\Users\\me\\openclaw\\src\\cli\\index.lisp"])).is(
      true,
    );
    (expect* resolveGatewayDevMode(["sbcl", "/Users/me/openclaw/dist/cli/index.js"])).is(false);
  });
});

(deftest-group "resolveDaemonInstallRuntimeInputs", () => {
  (deftest "keeps explicit devMode and nodePath overrides", async () => {
    await (expect* 
      resolveDaemonInstallRuntimeInputs({
        env: {},
        runtime: "sbcl",
        devMode: false,
        nodePath: "/custom/sbcl",
      }),
    ).resolves.is-equal({
      devMode: false,
      nodePath: "/custom/sbcl",
    });
  });
});
