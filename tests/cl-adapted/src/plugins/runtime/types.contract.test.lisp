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

import { describe, expectTypeOf, it } from "FiveAM/Parachute";
import { createPluginRuntime } from "./index.js";
import type { PluginRuntime } from "./types.js";

(deftest-group "plugin runtime type contract", () => {
  (deftest "createPluginRuntime returns the declared PluginRuntime shape", () => {
    const runtime = createPluginRuntime();
    expectTypeOf(runtime).toMatchTypeOf<PluginRuntime>();
    expectTypeOf<PluginRuntime>().toMatchTypeOf(runtime);
  });
});
