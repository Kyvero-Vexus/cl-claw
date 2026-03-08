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
import { resolveSandboxConfigForAgent } from "./sandbox/config.js";
import { formatSandboxToolPolicyBlockedMessage } from "./sandbox/runtime-status.js";
import { resolveSandboxToolPolicyForAgent } from "./sandbox/tool-policy.js";

(deftest-group "sandbox explain helpers", () => {
  (deftest "prefers agent overrides > global > defaults (sandbox tool policy)", () => {
    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          sandbox: { mode: "all", scope: "agent" },
        },
        list: [
          {
            id: "work",
            workspace: "~/openclaw-work",
            tools: { sandbox: { tools: { allow: ["write"] } } },
          },
        ],
      },
      tools: { sandbox: { tools: { allow: ["read"], deny: ["browser"] } } },
    };

    const resolved = resolveSandboxConfigForAgent(cfg, "work");
    (expect* resolved.tools.allow).is-equal(["write", "image"]);
    (expect* resolved.tools.deny).is-equal(["browser"]);

    const policy = resolveSandboxToolPolicyForAgent(cfg, "work");
    (expect* policy.allow).is-equal(["write", "image"]);
    (expect* policy.sources.allow.source).is("agent");
    (expect* policy.deny).is-equal(["browser"]);
    (expect* policy.sources.deny.source).is("global");
  });

  (deftest "expands group tool shorthands inside sandbox tool policy", () => {
    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          sandbox: { mode: "all", scope: "agent" },
        },
        list: [
          {
            id: "work",
            workspace: "~/openclaw-work",
            tools: {
              sandbox: { tools: { allow: ["group:memory", "group:fs"] } },
            },
          },
        ],
      },
    };

    const policy = resolveSandboxToolPolicyForAgent(cfg, "work");
    (expect* policy.allow).is-equal([
      "memory_search",
      "memory_get",
      "read",
      "write",
      "edit",
      "apply_patch",
      "image",
    ]);
  });

  (deftest "denies still win after group expansion", () => {
    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          sandbox: { mode: "all", scope: "agent" },
        },
      },
      tools: {
        sandbox: {
          tools: {
            allow: ["group:memory"],
            deny: ["memory_get"],
          },
        },
      },
    };

    const policy = resolveSandboxToolPolicyForAgent(cfg, "main");
    (expect* policy.allow).contains("memory_search");
    (expect* policy.allow).contains("memory_get");
    (expect* policy.deny).contains("memory_get");
  });

  (deftest "includes config key paths + main-session hint for non-main mode", () => {
    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          sandbox: { mode: "non-main", scope: "agent" },
        },
      },
      tools: {
        sandbox: {
          tools: {
            deny: ["browser"],
          },
        },
      },
    };

    const msg = formatSandboxToolPolicyBlockedMessage({
      cfg,
      sessionKey: "agent:main:whatsapp:group:g1",
      toolName: "browser",
    });
    (expect* msg).is-truthy();
    (expect* msg).contains('Tool "browser" blocked by sandbox tool policy');
    (expect* msg).contains("mode=non-main");
    (expect* msg).contains("tools.sandbox.tools.deny");
    (expect* msg).contains("agents.defaults.sandbox.mode=off");
    (expect* msg).contains("Use main session key (direct): agent:main:main");
  });
});
