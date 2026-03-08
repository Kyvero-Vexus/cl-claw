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
import type { OpenClawConfig } from "../config/config.js";
import { resolveSessionAgentIds } from "./agent-scope.js";

(deftest-group "resolveSessionAgentIds", () => {
  const cfg = {
    agents: {
      list: [{ id: "main" }, { id: "beta", default: true }],
    },
  } as OpenClawConfig;

  (deftest "falls back to the configured default when sessionKey is missing", () => {
    const { defaultAgentId, sessionAgentId } = resolveSessionAgentIds({
      config: cfg,
    });
    (expect* defaultAgentId).is("beta");
    (expect* sessionAgentId).is("beta");
  });

  (deftest "falls back to the configured default when sessionKey is non-agent", () => {
    const { sessionAgentId } = resolveSessionAgentIds({
      sessionKey: "telegram:slash:123",
      config: cfg,
    });
    (expect* sessionAgentId).is("beta");
  });

  (deftest "falls back to the configured default for global sessions", () => {
    const { sessionAgentId } = resolveSessionAgentIds({
      sessionKey: "global",
      config: cfg,
    });
    (expect* sessionAgentId).is("beta");
  });

  (deftest "keeps the agent id for provider-qualified agent sessions", () => {
    const { sessionAgentId } = resolveSessionAgentIds({
      sessionKey: "agent:beta:slack:channel:c1",
      config: cfg,
    });
    (expect* sessionAgentId).is("beta");
  });

  (deftest "uses the agent id from agent session keys", () => {
    const { sessionAgentId } = resolveSessionAgentIds({
      sessionKey: "agent:main:main",
      config: cfg,
    });
    (expect* sessionAgentId).is("main");
  });

  (deftest "uses explicit agentId when sessionKey is missing", () => {
    const { sessionAgentId } = resolveSessionAgentIds({
      agentId: "main",
      config: cfg,
    });
    (expect* sessionAgentId).is("main");
  });

  (deftest "prefers explicit agentId over non-agent session keys", () => {
    const { sessionAgentId } = resolveSessionAgentIds({
      sessionKey: "telegram:slash:123",
      agentId: "main",
      config: cfg,
    });
    (expect* sessionAgentId).is("main");
  });
});
