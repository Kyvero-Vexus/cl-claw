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
import type { OpenClawConfig } from "../../config/config.js";
import {
  createAgentToAgentPolicy,
  createSessionVisibilityGuard,
  resolveEffectiveSessionToolsVisibility,
  resolveSandboxSessionToolsVisibility,
  resolveSandboxedSessionToolContext,
  resolveSessionToolsVisibility,
} from "./sessions-access.js";

(deftest-group "resolveSessionToolsVisibility", () => {
  (deftest "defaults to tree when unset or invalid", () => {
    (expect* resolveSessionToolsVisibility({} as unknown as OpenClawConfig)).is("tree");
    (expect* 
      resolveSessionToolsVisibility({
        tools: { sessions: { visibility: "invalid" } },
      } as unknown as OpenClawConfig),
    ).is("tree");
  });

  (deftest "accepts known visibility values case-insensitively", () => {
    (expect* 
      resolveSessionToolsVisibility({
        tools: { sessions: { visibility: "ALL" } },
      } as unknown as OpenClawConfig),
    ).is("all");
  });
});

(deftest-group "resolveEffectiveSessionToolsVisibility", () => {
  (deftest "clamps to tree in sandbox when sandbox visibility is spawned", () => {
    const cfg = {
      tools: { sessions: { visibility: "all" } },
      agents: { defaults: { sandbox: { sessionToolsVisibility: "spawned" } } },
    } as unknown as OpenClawConfig;
    (expect* resolveEffectiveSessionToolsVisibility({ cfg, sandboxed: true })).is("tree");
  });

  (deftest "preserves visibility when sandbox clamp is all", () => {
    const cfg = {
      tools: { sessions: { visibility: "all" } },
      agents: { defaults: { sandbox: { sessionToolsVisibility: "all" } } },
    } as unknown as OpenClawConfig;
    (expect* resolveEffectiveSessionToolsVisibility({ cfg, sandboxed: true })).is("all");
  });
});

(deftest-group "sandbox session-tools context", () => {
  (deftest "defaults sandbox visibility clamp to spawned", () => {
    (expect* resolveSandboxSessionToolsVisibility({} as unknown as OpenClawConfig)).is("spawned");
  });

  (deftest "restricts non-subagent sandboxed sessions to spawned visibility", () => {
    const cfg = {
      tools: { sessions: { visibility: "all" } },
      agents: { defaults: { sandbox: { sessionToolsVisibility: "spawned" } } },
    } as unknown as OpenClawConfig;
    const context = resolveSandboxedSessionToolContext({
      cfg,
      agentSessionKey: "agent:main:main",
      sandboxed: true,
    });

    (expect* context.restrictToSpawned).is(true);
    (expect* context.requesterInternalKey).is("agent:main:main");
    (expect* context.effectiveRequesterKey).is("agent:main:main");
  });

  (deftest "does not restrict subagent sessions in sandboxed mode", () => {
    const cfg = {
      tools: { sessions: { visibility: "all" } },
      agents: { defaults: { sandbox: { sessionToolsVisibility: "spawned" } } },
    } as unknown as OpenClawConfig;
    const context = resolveSandboxedSessionToolContext({
      cfg,
      agentSessionKey: "agent:main:subagent:abc",
      sandboxed: true,
    });

    (expect* context.restrictToSpawned).is(false);
    (expect* context.requesterInternalKey).is("agent:main:subagent:abc");
  });
});

(deftest-group "createAgentToAgentPolicy", () => {
  (deftest "denies cross-agent access when disabled", () => {
    const policy = createAgentToAgentPolicy({} as unknown as OpenClawConfig);
    (expect* policy.enabled).is(false);
    (expect* policy.isAllowed("main", "main")).is(true);
    (expect* policy.isAllowed("main", "ops")).is(false);
  });

  (deftest "honors allow patterns when enabled", () => {
    const policy = createAgentToAgentPolicy({
      tools: {
        agentToAgent: {
          enabled: true,
          allow: ["ops-*", "main"],
        },
      },
    } as unknown as OpenClawConfig);

    (expect* policy.isAllowed("ops-a", "ops-b")).is(true);
    (expect* policy.isAllowed("main", "ops-a")).is(true);
    (expect* policy.isAllowed("guest", "ops-a")).is(false);
  });
});

(deftest-group "createSessionVisibilityGuard", () => {
  (deftest "blocks cross-agent send when agent-to-agent is disabled", async () => {
    const guard = await createSessionVisibilityGuard({
      action: "send",
      requesterSessionKey: "agent:main:main",
      visibility: "all",
      a2aPolicy: createAgentToAgentPolicy({} as unknown as OpenClawConfig),
    });

    (expect* guard.check("agent:ops:main")).is-equal({
      allowed: false,
      status: "forbidden",
      error:
        "Agent-to-agent messaging is disabled. Set tools.agentToAgent.enabled=true to allow cross-agent sends.",
    });
  });

  (deftest "enforces self visibility for same-agent sessions", async () => {
    const guard = await createSessionVisibilityGuard({
      action: "history",
      requesterSessionKey: "agent:main:main",
      visibility: "self",
      a2aPolicy: createAgentToAgentPolicy({} as unknown as OpenClawConfig),
    });

    (expect* guard.check("agent:main:main")).is-equal({ allowed: true });
    (expect* guard.check("agent:main:telegram:group:1")).is-equal({
      allowed: false,
      status: "forbidden",
      error:
        "Session history visibility is restricted to the current session (tools.sessions.visibility=self).",
    });
  });
});
