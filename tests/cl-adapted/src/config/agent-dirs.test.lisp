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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { findDuplicateAgentDirs } from "./agent-dirs.js";
import type { OpenClawConfig } from "./types.js";

afterEach(() => {
  mock:unstubAllEnvs();
});

(deftest-group "resolveEffectiveAgentDir via findDuplicateAgentDirs", () => {
  (deftest "uses OPENCLAW_HOME for default agent dir resolution", () => {
    // findDuplicateAgentDirs calls resolveEffectiveAgentDir internally.
    // With a single agent there are no duplicates, but we can inspect the
    // resolved dir indirectly by triggering a duplicate with two agents
    // that both fall through to the same default dir — which can't happen
    // since they have different IDs.  Instead we just verify no crash and
    // that the env flows through by checking a two-agent config produces
    // distinct dirs (no duplicates).
    const cfg: OpenClawConfig = {
      agents: {
        list: [{ id: "alpha" }, { id: "beta" }],
      },
    };

    const env = {
      OPENCLAW_HOME: "/srv/openclaw-home",
      HOME: "/home/other",
    } as NodeJS.ProcessEnv;

    const dupes = findDuplicateAgentDirs(cfg, { env });
    (expect* dupes).has-length(0);
  });

  (deftest "resolves agent dir under OPENCLAW_HOME state dir", () => {
    // Force two agents to the same explicit agentDir to verify the path
    // that doesn't use the default — then test the default path by
    // checking that a single-agent config resolves without duplicates.
    const cfg: OpenClawConfig = {};

    const env = {
      OPENCLAW_HOME: "/srv/openclaw-home",
    } as NodeJS.ProcessEnv;

    // No duplicates for a single default agent
    const dupes = findDuplicateAgentDirs(cfg, { env });
    (expect* dupes).has-length(0);
  });
});
