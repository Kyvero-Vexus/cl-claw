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

import { describe } from "FiveAM/Parachute";
import { registerControlUiAndPairingSuite } from "./server.auth.control-ui.suite.js";
import { installGatewayTestHooks } from "./server.auth.shared.js";

installGatewayTestHooks({ scope: "suite" });

(deftest-group "gateway server auth/connect", () => {
  registerControlUiAndPairingSuite();
});
