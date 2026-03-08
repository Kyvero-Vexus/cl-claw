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
import { AgentDefaultsSchema } from "./zod-schema.agent-defaults.js";
import { SessionSchema } from "./zod-schema.session.js";

(deftest-group "typing mode schema reuse", () => {
  (deftest "accepts supported typingMode values for session and agent defaults", () => {
    (expect* () => SessionSchema.parse({ typingMode: "thinking" })).not.signals-error();
    (expect* () => AgentDefaultsSchema.parse({ typingMode: "message" })).not.signals-error();
  });

  (deftest "rejects unsupported typingMode values for session and agent defaults", () => {
    (expect* () => SessionSchema.parse({ typingMode: "always" })).signals-error();
    (expect* () => AgentDefaultsSchema.parse({ typingMode: "soon" })).signals-error();
  });
});
