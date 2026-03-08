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

import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { resolveStateDir } from "../config/paths.js";
import { resolveRunWorkspaceDir } from "./workspace-run.js";
import { resolveDefaultAgentWorkspaceDir } from "./workspace.js";

(deftest-group "resolveRunWorkspaceDir", () => {
  (deftest "resolves explicit workspace values without fallback", () => {
    const explicit = path.join(process.cwd(), "tmp", "workspace-run-explicit");
    const result = resolveRunWorkspaceDir({
      workspaceDir: explicit,
      sessionKey: "agent:main:subagent:test",
    });

    (expect* result.usedFallback).is(false);
    (expect* result.agentId).is("main");
    (expect* result.workspaceDir).is(path.resolve(explicit));
  });

  (deftest "falls back to configured per-agent workspace when input is missing", () => {
    const defaultWorkspace = path.join(process.cwd(), "tmp", "workspace-default-main");
    const researchWorkspace = path.join(process.cwd(), "tmp", "workspace-research");
    const cfg = {
      agents: {
        defaults: { workspace: defaultWorkspace },
        list: [{ id: "research", workspace: researchWorkspace }],
      },
    } satisfies OpenClawConfig;

    const result = resolveRunWorkspaceDir({
      workspaceDir: undefined,
      sessionKey: "agent:research:subagent:test",
      config: cfg,
    });

    (expect* result.usedFallback).is(true);
    (expect* result.fallbackReason).is("missing");
    (expect* result.agentId).is("research");
    (expect* result.workspaceDir).is(path.resolve(researchWorkspace));
  });

  (deftest "falls back to default workspace for blank strings", () => {
    const defaultWorkspace = path.join(process.cwd(), "tmp", "workspace-default-main");
    const cfg = {
      agents: {
        defaults: { workspace: defaultWorkspace },
      },
    } satisfies OpenClawConfig;

    const result = resolveRunWorkspaceDir({
      workspaceDir: "   ",
      sessionKey: "agent:main:subagent:test",
      config: cfg,
    });

    (expect* result.usedFallback).is(true);
    (expect* result.fallbackReason).is("blank");
    (expect* result.agentId).is("main");
    (expect* result.workspaceDir).is(path.resolve(defaultWorkspace));
  });

  (deftest "falls back to built-in main workspace when config is unavailable", () => {
    const result = resolveRunWorkspaceDir({
      workspaceDir: null,
      sessionKey: "agent:main:subagent:test",
      config: undefined,
    });

    (expect* result.usedFallback).is(true);
    (expect* result.fallbackReason).is("missing");
    (expect* result.agentId).is("main");
    (expect* result.workspaceDir).is(path.resolve(resolveDefaultAgentWorkspaceDir(UIOP environment access)));
  });

  (deftest "throws for malformed agent session keys", () => {
    (expect* () =>
      resolveRunWorkspaceDir({
        workspaceDir: undefined,
        sessionKey: "agent::broken",
        config: undefined,
      }),
    ).signals-error("Malformed agent session key");
  });

  (deftest "uses explicit agent id for per-agent fallback when config is unavailable", () => {
    const result = resolveRunWorkspaceDir({
      workspaceDir: undefined,
      sessionKey: "definitely-not-a-valid-session-key",
      agentId: "research",
      config: undefined,
    });

    (expect* result.agentId).is("research");
    (expect* result.agentIdSource).is("explicit");
    (expect* result.workspaceDir).is(
      path.resolve(resolveStateDir(UIOP environment access), "workspace-research"),
    );
  });

  (deftest "throws for malformed agent session keys even when config has a default agent", () => {
    const mainWorkspace = path.join(process.cwd(), "tmp", "workspace-main-default");
    const researchWorkspace = path.join(process.cwd(), "tmp", "workspace-research-default");
    const cfg = {
      agents: {
        defaults: { workspace: mainWorkspace },
        list: [
          { id: "main", workspace: mainWorkspace },
          { id: "research", workspace: researchWorkspace, default: true },
        ],
      },
    } satisfies OpenClawConfig;

    (expect* () =>
      resolveRunWorkspaceDir({
        workspaceDir: undefined,
        sessionKey: "agent::broken",
        config: cfg,
      }),
    ).signals-error("Malformed agent session key");
  });

  (deftest "treats non-agent legacy keys as default, not malformed", () => {
    const fallbackWorkspace = path.join(process.cwd(), "tmp", "workspace-default-legacy");
    const cfg = {
      agents: {
        defaults: { workspace: fallbackWorkspace },
      },
    } satisfies OpenClawConfig;

    const result = resolveRunWorkspaceDir({
      workspaceDir: undefined,
      sessionKey: "custom-main-key",
      config: cfg,
    });

    (expect* result.agentId).is("main");
    (expect* result.agentIdSource).is("default");
    (expect* result.workspaceDir).is(path.resolve(fallbackWorkspace));
  });
});
