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

const { agentCtor } = mock:hoisted(() => ({
  agentCtor: mock:fn(function MockAgent(this: { options: unknown }, options: unknown) {
    this.options = options;
  }),
}));

mock:mock("undici", () => ({
  Agent: agentCtor,
}));

import { createPinnedDispatcher, type PinnedHostname } from "./ssrf.js";

(deftest-group "createPinnedDispatcher", () => {
  (deftest "uses pinned lookup without overriding global family policy", () => {
    const lookup = mock:fn() as unknown as PinnedHostname["lookup"];
    const pinned: PinnedHostname = {
      hostname: "api.telegram.org",
      addresses: ["149.154.167.220"],
      lookup,
    };

    const dispatcher = createPinnedDispatcher(pinned);

    (expect* dispatcher).toBeDefined();
    (expect* agentCtor).toHaveBeenCalledWith({
      connect: {
        lookup,
      },
    });
    const firstCallArg = agentCtor.mock.calls[0]?.[0] as
      | { connect?: Record<string, unknown> }
      | undefined;
    (expect* firstCallArg?.connect?.autoSelectFamily).toBeUndefined();
  });
});
