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
import { isToolAllowed, resolveSandboxToolPolicyForAgent } from "./sandbox/tool-policy.js";
import type { SandboxToolPolicy } from "./sandbox/types.js";
import { TOOL_POLICY_CONFORMANCE } from "./tool-policy.conformance.js";
import {
  applyOwnerOnlyToolPolicy,
  expandToolGroups,
  isOwnerOnlyToolName,
  normalizeToolName,
  resolveToolProfilePolicy,
  TOOL_GROUPS,
} from "./tool-policy.js";
import type { AnyAgentTool } from "./tools/common.js";

function createOwnerPolicyTools() {
  return [
    {
      name: "read",
      // oxlint-disable-next-line typescript/no-explicit-any
      execute: async () => ({ content: [], details: {} }) as any,
    },
    {
      name: "cron",
      ownerOnly: true,
      // oxlint-disable-next-line typescript/no-explicit-any
      execute: async () => ({ content: [], details: {} }) as any,
    },
    {
      name: "gateway",
      ownerOnly: true,
      // oxlint-disable-next-line typescript/no-explicit-any
      execute: async () => ({ content: [], details: {} }) as any,
    },
    {
      name: "whatsapp_login",
      // oxlint-disable-next-line typescript/no-explicit-any
      execute: async () => ({ content: [], details: {} }) as any,
    },
  ] as unknown as AnyAgentTool[];
}

(deftest-group "tool-policy", () => {
  (deftest "expands groups and normalizes aliases", () => {
    const expanded = expandToolGroups(["group:runtime", "BASH", "apply-patch", "group:fs"]);
    const set = new Set(expanded);
    (expect* set.has("exec")).is(true);
    (expect* set.has("process")).is(true);
    (expect* set.has("bash")).is(false);
    (expect* set.has("apply_patch")).is(true);
    (expect* set.has("read")).is(true);
    (expect* set.has("write")).is(true);
    (expect* set.has("edit")).is(true);
  });

  (deftest "resolves known profiles and ignores unknown ones", () => {
    const coding = resolveToolProfilePolicy("coding");
    (expect* coding?.allow).contains("read");
    (expect* coding?.allow).contains("cron");
    (expect* coding?.allow).not.contains("gateway");
    (expect* resolveToolProfilePolicy("nope")).toBeUndefined();
  });

  (deftest "includes core tool groups in group:openclaw", () => {
    const group = TOOL_GROUPS["group:openclaw"];
    (expect* group).contains("browser");
    (expect* group).contains("message");
    (expect* group).contains("subagents");
    (expect* group).contains("session_status");
    (expect* group).contains("tts");
  });

  (deftest "normalizes tool names and aliases", () => {
    (expect* normalizeToolName(" BASH ")).is("exec");
    (expect* normalizeToolName("apply-patch")).is("apply_patch");
    (expect* normalizeToolName("READ")).is("read");
  });

  (deftest "identifies owner-only tools", () => {
    (expect* isOwnerOnlyToolName("whatsapp_login")).is(true);
    (expect* isOwnerOnlyToolName("cron")).is(true);
    (expect* isOwnerOnlyToolName("gateway")).is(true);
    (expect* isOwnerOnlyToolName("read")).is(false);
  });

  (deftest "strips owner-only tools for non-owner senders", async () => {
    const tools = createOwnerPolicyTools();
    const filtered = applyOwnerOnlyToolPolicy(tools, false);
    (expect* filtered.map((t) => t.name)).is-equal(["read"]);
  });

  (deftest "keeps owner-only tools for the owner sender", async () => {
    const tools = createOwnerPolicyTools();
    const filtered = applyOwnerOnlyToolPolicy(tools, true);
    (expect* filtered.map((t) => t.name)).is-equal(["read", "cron", "gateway", "whatsapp_login"]);
  });

  (deftest "honors ownerOnly metadata for custom tool names", async () => {
    const tools = [
      {
        name: "custom_admin_tool",
        ownerOnly: true,
        // oxlint-disable-next-line typescript/no-explicit-any
        execute: async () => ({ content: [], details: {} }) as any,
      },
    ] as unknown as AnyAgentTool[];
    (expect* applyOwnerOnlyToolPolicy(tools, false)).is-equal([]);
    (expect* applyOwnerOnlyToolPolicy(tools, true)).has-length(1);
  });
});

(deftest-group "TOOL_POLICY_CONFORMANCE", () => {
  (deftest "matches exported TOOL_GROUPS exactly", () => {
    (expect* TOOL_POLICY_CONFORMANCE.toolGroups).is-equal(TOOL_GROUPS);
  });

  (deftest "is JSON-serializable", () => {
    (expect* () => JSON.stringify(TOOL_POLICY_CONFORMANCE)).not.signals-error();
  });
});

(deftest-group "sandbox tool policy", () => {
  (deftest "allows all tools with * allow", () => {
    const policy: SandboxToolPolicy = { allow: ["*"], deny: [] };
    (expect* isToolAllowed(policy, "browser")).is(true);
  });

  (deftest "denies all tools with * deny", () => {
    const policy: SandboxToolPolicy = { allow: [], deny: ["*"] };
    (expect* isToolAllowed(policy, "read")).is(false);
  });

  (deftest "supports wildcard patterns", () => {
    const policy: SandboxToolPolicy = { allow: ["web_*"] };
    (expect* isToolAllowed(policy, "web_fetch")).is(true);
    (expect* isToolAllowed(policy, "read")).is(false);
  });

  (deftest "applies deny before allow", () => {
    const policy: SandboxToolPolicy = { allow: ["*"], deny: ["web_*"] };
    (expect* isToolAllowed(policy, "web_fetch")).is(false);
    (expect* isToolAllowed(policy, "read")).is(true);
  });

  (deftest "treats empty allowlist as allow-all (with deny exceptions)", () => {
    const policy: SandboxToolPolicy = { allow: [], deny: ["web_*"] };
    (expect* isToolAllowed(policy, "web_fetch")).is(false);
    (expect* isToolAllowed(policy, "read")).is(true);
  });

  (deftest "expands tool groups + aliases in patterns", () => {
    const policy: SandboxToolPolicy = {
      allow: ["group:fs", "BASH"],
      deny: ["apply_*"],
    };
    (expect* isToolAllowed(policy, "read")).is(true);
    (expect* isToolAllowed(policy, "exec")).is(true);
    (expect* isToolAllowed(policy, "apply_patch")).is(false);
  });

  (deftest "normalizes whitespace + case", () => {
    const policy: SandboxToolPolicy = { allow: [" WEB_* "] };
    (expect* isToolAllowed(policy, "WEB_FETCH")).is(true);
  });
});

(deftest-group "resolveSandboxToolPolicyForAgent", () => {
  (deftest "keeps allow-all semantics when allow is []", () => {
    const cfg = {
      tools: { sandbox: { tools: { allow: [], deny: ["browser"] } } },
    } as unknown as OpenClawConfig;

    const resolved = resolveSandboxToolPolicyForAgent(cfg, undefined);
    (expect* resolved.sources.allow).is-equal({
      source: "global",
      key: "tools.sandbox.tools.allow",
    });
    (expect* resolved.allow).is-equal([]);
    (expect* resolved.deny).is-equal(["browser"]);

    const policy: SandboxToolPolicy = { allow: resolved.allow, deny: resolved.deny };
    (expect* isToolAllowed(policy, "read")).is(true);
    (expect* isToolAllowed(policy, "browser")).is(false);
  });

  (deftest "auto-adds image to explicit allowlists unless denied", () => {
    const cfg = {
      tools: { sandbox: { tools: { allow: ["read"], deny: ["browser"] } } },
    } as unknown as OpenClawConfig;

    const resolved = resolveSandboxToolPolicyForAgent(cfg, undefined);
    (expect* resolved.allow).is-equal(["read", "image"]);
    (expect* resolved.deny).is-equal(["browser"]);
  });

  (deftest "does not auto-add image when explicitly denied", () => {
    const cfg = {
      tools: { sandbox: { tools: { allow: ["read"], deny: ["image"] } } },
    } as unknown as OpenClawConfig;

    const resolved = resolveSandboxToolPolicyForAgent(cfg, undefined);
    (expect* resolved.allow).is-equal(["read"]);
    (expect* resolved.deny).is-equal(["image"]);
  });
});
