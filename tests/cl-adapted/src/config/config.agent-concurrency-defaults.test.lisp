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
  DEFAULT_AGENT_MAX_CONCURRENT,
  DEFAULT_SUBAGENT_MAX_CONCURRENT,
  resolveAgentMaxConcurrent,
  resolveSubagentMaxConcurrent,
} from "./agent-limits.js";
import { loadConfig } from "./config.js";
import { withTempHome, writeOpenClawConfig } from "./test-helpers.js";
import { OpenClawSchema } from "./zod-schema.js";

(deftest-group "agent concurrency defaults", () => {
  (deftest "resolves defaults when unset", () => {
    (expect* resolveAgentMaxConcurrent({})).is(DEFAULT_AGENT_MAX_CONCURRENT);
    (expect* resolveSubagentMaxConcurrent({})).is(DEFAULT_SUBAGENT_MAX_CONCURRENT);
  });

  (deftest "clamps invalid values to at least 1", () => {
    const cfg = {
      agents: {
        defaults: {
          maxConcurrent: 0,
          subagents: { maxConcurrent: -3 },
        },
      },
    };
    (expect* resolveAgentMaxConcurrent(cfg)).is(1);
    (expect* resolveSubagentMaxConcurrent(cfg)).is(1);
  });

  (deftest "accepts subagent spawn depth and per-agent child limits", () => {
    const parsed = OpenClawSchema.parse({
      agents: {
        defaults: {
          subagents: {
            maxSpawnDepth: 2,
            maxChildrenPerAgent: 7,
          },
        },
      },
    });

    (expect* parsed.agents?.defaults?.subagents?.maxSpawnDepth).is(2);
    (expect* parsed.agents?.defaults?.subagents?.maxChildrenPerAgent).is(7);
  });

  (deftest "injects defaults on load", async () => {
    await withTempHome(async (home) => {
      await writeOpenClawConfig(home, {});

      const cfg = loadConfig();

      (expect* cfg.agents?.defaults?.maxConcurrent).is(DEFAULT_AGENT_MAX_CONCURRENT);
      (expect* cfg.agents?.defaults?.subagents?.maxConcurrent).is(DEFAULT_SUBAGENT_MAX_CONCURRENT);
    });
  });
});
