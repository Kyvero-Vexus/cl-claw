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
import { resolveCronAgentSessionKey } from "./session-key.js";

(deftest-group "resolveCronAgentSessionKey", () => {
  (deftest "builds an agent-scoped key for legacy aliases", () => {
    (expect* resolveCronAgentSessionKey({ sessionKey: "main", agentId: "main" })).is(
      "agent:main:main",
    );
  });

  (deftest "preserves canonical agent keys instead of prefixing twice", () => {
    (expect* resolveCronAgentSessionKey({ sessionKey: "agent:main:main", agentId: "main" })).is(
      "agent:main:main",
    );
  });

  (deftest "normalizes canonical keys to lowercase before reuse", () => {
    (expect* 
      resolveCronAgentSessionKey({ sessionKey: "AGENT:Main:Hook:Webhook:42", agentId: "x" }),
    ).is("agent:main:hook:webhook:42");
  });

  (deftest "keeps hook keys scoped under the target agent", () => {
    (expect* resolveCronAgentSessionKey({ sessionKey: "hook:webhook:42", agentId: "main" })).is(
      "agent:main:hook:webhook:42",
    );
  });
});
