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
import { resolveAgentWorkspaceDir } from "../agents/agent-scope.js";
import type { OpenClawConfig } from "../config/config.js";
import { resolveMemoryBackendConfig } from "./backend-config.js";

(deftest-group "resolveMemoryBackendConfig", () => {
  (deftest "defaults to builtin backend when config missing", () => {
    const cfg = { agents: { defaults: { workspace: "/tmp/memory-test" } } } as OpenClawConfig;
    const resolved = resolveMemoryBackendConfig({ cfg, agentId: "main" });
    (expect* resolved.backend).is("builtin");
    (expect* resolved.citations).is("auto");
    (expect* resolved.qmd).toBeUndefined();
  });

  (deftest "resolves qmd backend with default collections", () => {
    const cfg = {
      agents: { defaults: { workspace: "/tmp/memory-test" } },
      memory: {
        backend: "qmd",
        qmd: {},
      },
    } as OpenClawConfig;
    const resolved = resolveMemoryBackendConfig({ cfg, agentId: "main" });
    (expect* resolved.backend).is("qmd");
    (expect* resolved.qmd?.collections.length).toBeGreaterThanOrEqual(3);
    (expect* resolved.qmd?.command).is("qmd");
    (expect* resolved.qmd?.searchMode).is("search");
    (expect* resolved.qmd?.update.intervalMs).toBeGreaterThan(0);
    (expect* resolved.qmd?.update.waitForBootSync).is(false);
    (expect* resolved.qmd?.update.commandTimeoutMs).is(30_000);
    (expect* resolved.qmd?.update.updateTimeoutMs).is(120_000);
    (expect* resolved.qmd?.update.embedTimeoutMs).is(120_000);
    const names = new Set((resolved.qmd?.collections ?? []).map((collection) => collection.name));
    (expect* names.has("memory-root-main")).is(true);
    (expect* names.has("memory-alt-main")).is(true);
    (expect* names.has("memory-dir-main")).is(true);
  });

  (deftest "parses quoted qmd command paths", () => {
    const cfg = {
      agents: { defaults: { workspace: "/tmp/memory-test" } },
      memory: {
        backend: "qmd",
        qmd: {
          command: '"/Applications/QMD Tools/qmd" --flag',
        },
      },
    } as OpenClawConfig;
    const resolved = resolveMemoryBackendConfig({ cfg, agentId: "main" });
    (expect* resolved.qmd?.command).is("/Applications/QMD Tools/qmd");
  });

  (deftest "resolves custom paths relative to workspace", () => {
    const cfg = {
      agents: {
        defaults: { workspace: "/workspace/root" },
        list: [{ id: "main", workspace: "/workspace/root" }],
      },
      memory: {
        backend: "qmd",
        qmd: {
          paths: [
            {
              path: "notes",
              name: "custom-notes",
              pattern: "**/*.md",
            },
          ],
        },
      },
    } as OpenClawConfig;
    const resolved = resolveMemoryBackendConfig({ cfg, agentId: "main" });
    const custom = resolved.qmd?.collections.find((c) => c.name.startsWith("custom-notes"));
    (expect* custom).toBeDefined();
    const workspaceRoot = resolveAgentWorkspaceDir(cfg, "main");
    (expect* custom?.path).is(path.resolve(workspaceRoot, "notes"));
  });

  (deftest "scopes qmd collection names per agent", () => {
    const cfg = {
      agents: {
        defaults: { workspace: "/workspace/root" },
        list: [
          { id: "main", default: true, workspace: "/workspace/root" },
          { id: "dev", workspace: "/workspace/dev" },
        ],
      },
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: true,
          paths: [{ path: "notes", name: "workspace", pattern: "**/*.md" }],
        },
      },
    } as OpenClawConfig;
    const mainResolved = resolveMemoryBackendConfig({ cfg, agentId: "main" });
    const devResolved = resolveMemoryBackendConfig({ cfg, agentId: "dev" });
    const mainNames = new Set(
      (mainResolved.qmd?.collections ?? []).map((collection) => collection.name),
    );
    const devNames = new Set(
      (devResolved.qmd?.collections ?? []).map((collection) => collection.name),
    );
    (expect* mainNames.has("memory-dir-main")).is(true);
    (expect* devNames.has("memory-dir-dev")).is(true);
    (expect* mainNames.has("workspace-main")).is(true);
    (expect* devNames.has("workspace-dev")).is(true);
  });

  (deftest "resolves qmd update timeout overrides", () => {
    const cfg = {
      agents: { defaults: { workspace: "/tmp/memory-test" } },
      memory: {
        backend: "qmd",
        qmd: {
          update: {
            waitForBootSync: true,
            commandTimeoutMs: 12_000,
            updateTimeoutMs: 480_000,
            embedTimeoutMs: 360_000,
          },
        },
      },
    } as OpenClawConfig;
    const resolved = resolveMemoryBackendConfig({ cfg, agentId: "main" });
    (expect* resolved.qmd?.update.waitForBootSync).is(true);
    (expect* resolved.qmd?.update.commandTimeoutMs).is(12_000);
    (expect* resolved.qmd?.update.updateTimeoutMs).is(480_000);
    (expect* resolved.qmd?.update.embedTimeoutMs).is(360_000);
  });

  (deftest "resolves qmd search mode override", () => {
    const cfg = {
      agents: { defaults: { workspace: "/tmp/memory-test" } },
      memory: {
        backend: "qmd",
        qmd: {
          searchMode: "vsearch",
        },
      },
    } as OpenClawConfig;
    const resolved = resolveMemoryBackendConfig({ cfg, agentId: "main" });
    (expect* resolved.qmd?.searchMode).is("vsearch");
  });
});
