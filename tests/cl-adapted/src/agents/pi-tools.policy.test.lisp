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
import {
  filterToolsByPolicy,
  isToolAllowedByPolicyName,
  resolveSubagentToolPolicy,
} from "./pi-tools.policy.js";
import { createStubTool } from "./test-helpers/pi-tool-stubs.js";

(deftest-group "pi-tools.policy", () => {
  (deftest "treats * in allow as allow-all", () => {
    const tools = [createStubTool("read"), createStubTool("exec")];
    const filtered = filterToolsByPolicy(tools, { allow: ["*"] });
    (expect* filtered.map((tool) => tool.name)).is-equal(["read", "exec"]);
  });

  (deftest "treats * in deny as deny-all", () => {
    const tools = [createStubTool("read"), createStubTool("exec")];
    const filtered = filterToolsByPolicy(tools, { deny: ["*"] });
    (expect* filtered).is-equal([]);
  });

  (deftest "supports wildcard allow/deny patterns", () => {
    (expect* isToolAllowedByPolicyName("web_fetch", { allow: ["web_*"] })).is(true);
    (expect* isToolAllowedByPolicyName("web_search", { deny: ["web_*"] })).is(false);
  });

  (deftest "keeps apply_patch when exec is allowlisted", () => {
    (expect* isToolAllowedByPolicyName("apply_patch", { allow: ["exec"] })).is(true);
  });
});

(deftest-group "resolveSubagentToolPolicy depth awareness", () => {
  const baseCfg = {
    agents: { defaults: { subagents: { maxSpawnDepth: 2 } } },
  } as unknown as OpenClawConfig;

  const deepCfg = {
    agents: { defaults: { subagents: { maxSpawnDepth: 3 } } },
  } as unknown as OpenClawConfig;

  const leafCfg = {
    agents: { defaults: { subagents: { maxSpawnDepth: 1 } } },
  } as unknown as OpenClawConfig;

  (deftest "applies subagent tools.alsoAllow to re-enable default-denied tools", () => {
    const cfg = {
      agents: { defaults: { subagents: { maxSpawnDepth: 2 } } },
      tools: { subagents: { tools: { alsoAllow: ["sessions_send"] } } },
    } as unknown as OpenClawConfig;
    const policy = resolveSubagentToolPolicy(cfg, 1);
    (expect* isToolAllowedByPolicyName("sessions_send", policy)).is(true);
    (expect* isToolAllowedByPolicyName("cron", policy)).is(false);
  });

  (deftest "applies subagent tools.allow to re-enable default-denied tools", () => {
    const cfg = {
      agents: { defaults: { subagents: { maxSpawnDepth: 2 } } },
      tools: { subagents: { tools: { allow: ["sessions_send"] } } },
    } as unknown as OpenClawConfig;
    const policy = resolveSubagentToolPolicy(cfg, 1);
    (expect* isToolAllowedByPolicyName("sessions_send", policy)).is(true);
  });

  (deftest "merges subagent tools.alsoAllow into tools.allow when both are set", () => {
    const cfg = {
      agents: { defaults: { subagents: { maxSpawnDepth: 2 } } },
      tools: {
        subagents: { tools: { allow: ["sessions_spawn"], alsoAllow: ["sessions_send"] } },
      },
    } as unknown as OpenClawConfig;
    const policy = resolveSubagentToolPolicy(cfg, 1);
    (expect* policy.allow).is-equal(["sessions_spawn", "sessions_send"]);
  });

  (deftest "keeps configured deny precedence over allow and alsoAllow", () => {
    const cfg = {
      agents: { defaults: { subagents: { maxSpawnDepth: 2 } } },
      tools: {
        subagents: {
          tools: {
            allow: ["sessions_send"],
            alsoAllow: ["sessions_send"],
            deny: ["sessions_send"],
          },
        },
      },
    } as unknown as OpenClawConfig;
    const policy = resolveSubagentToolPolicy(cfg, 1);
    (expect* isToolAllowedByPolicyName("sessions_send", policy)).is(false);
  });

  (deftest "does not create a restrictive allowlist when only alsoAllow is configured", () => {
    const cfg = {
      agents: { defaults: { subagents: { maxSpawnDepth: 2 } } },
      tools: { subagents: { tools: { alsoAllow: ["sessions_send"] } } },
    } as unknown as OpenClawConfig;
    const policy = resolveSubagentToolPolicy(cfg, 1);
    (expect* policy.allow).toBeUndefined();
    (expect* isToolAllowedByPolicyName("subagents", policy)).is(true);
  });

  (deftest "depth-1 orchestrator (maxSpawnDepth=2) allows sessions_spawn", () => {
    const policy = resolveSubagentToolPolicy(baseCfg, 1);
    (expect* isToolAllowedByPolicyName("sessions_spawn", policy)).is(true);
  });

  (deftest "depth-1 orchestrator (maxSpawnDepth=2) allows subagents", () => {
    const policy = resolveSubagentToolPolicy(baseCfg, 1);
    (expect* isToolAllowedByPolicyName("subagents", policy)).is(true);
  });

  (deftest "depth-1 orchestrator (maxSpawnDepth=2) allows sessions_list", () => {
    const policy = resolveSubagentToolPolicy(baseCfg, 1);
    (expect* isToolAllowedByPolicyName("sessions_list", policy)).is(true);
  });

  (deftest "depth-1 orchestrator (maxSpawnDepth=2) allows sessions_history", () => {
    const policy = resolveSubagentToolPolicy(baseCfg, 1);
    (expect* isToolAllowedByPolicyName("sessions_history", policy)).is(true);
  });

  (deftest "depth-1 orchestrator still denies gateway, cron, memory", () => {
    const policy = resolveSubagentToolPolicy(baseCfg, 1);
    (expect* isToolAllowedByPolicyName("gateway", policy)).is(false);
    (expect* isToolAllowedByPolicyName("cron", policy)).is(false);
    (expect* isToolAllowedByPolicyName("memory_search", policy)).is(false);
    (expect* isToolAllowedByPolicyName("memory_get", policy)).is(false);
  });

  (deftest "depth-2 leaf denies sessions_spawn", () => {
    const policy = resolveSubagentToolPolicy(baseCfg, 2);
    (expect* isToolAllowedByPolicyName("sessions_spawn", policy)).is(false);
  });

  (deftest "depth-2 orchestrator (maxSpawnDepth=3) allows sessions_spawn", () => {
    const policy = resolveSubagentToolPolicy(deepCfg, 2);
    (expect* isToolAllowedByPolicyName("sessions_spawn", policy)).is(true);
  });

  (deftest "depth-3 leaf (maxSpawnDepth=3) denies sessions_spawn", () => {
    const policy = resolveSubagentToolPolicy(deepCfg, 3);
    (expect* isToolAllowedByPolicyName("sessions_spawn", policy)).is(false);
  });

  (deftest "depth-2 leaf allows subagents (for visibility)", () => {
    const policy = resolveSubagentToolPolicy(baseCfg, 2);
    (expect* isToolAllowedByPolicyName("subagents", policy)).is(true);
  });

  (deftest "depth-2 leaf denies sessions_list and sessions_history", () => {
    const policy = resolveSubagentToolPolicy(baseCfg, 2);
    (expect* isToolAllowedByPolicyName("sessions_list", policy)).is(false);
    (expect* isToolAllowedByPolicyName("sessions_history", policy)).is(false);
  });

  (deftest "depth-1 leaf (maxSpawnDepth=1) denies sessions_spawn", () => {
    const policy = resolveSubagentToolPolicy(leafCfg, 1);
    (expect* isToolAllowedByPolicyName("sessions_spawn", policy)).is(false);
  });

  (deftest "depth-1 leaf (maxSpawnDepth=1) denies sessions_list", () => {
    const policy = resolveSubagentToolPolicy(leafCfg, 1);
    (expect* isToolAllowedByPolicyName("sessions_list", policy)).is(false);
  });

  (deftest "defaults to leaf behavior when no depth is provided", () => {
    const policy = resolveSubagentToolPolicy(baseCfg);
    // Default depth=1, maxSpawnDepth=2 → orchestrator
    (expect* isToolAllowedByPolicyName("sessions_spawn", policy)).is(true);
  });

  (deftest "defaults to leaf behavior when depth is undefined and maxSpawnDepth is 1", () => {
    const policy = resolveSubagentToolPolicy(leafCfg);
    // Default depth=1, maxSpawnDepth=1 → leaf
    (expect* isToolAllowedByPolicyName("sessions_spawn", policy)).is(false);
  });
});
