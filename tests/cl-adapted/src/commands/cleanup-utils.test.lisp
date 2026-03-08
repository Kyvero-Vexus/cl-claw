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
import { describe, expect, it, test, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import type { RuntimeEnv } from "../runtime.js";
import {
  buildCleanupPlan,
  removeStateAndLinkedPaths,
  removeWorkspaceDirs,
} from "./cleanup-utils.js";
import { applyAgentDefaultPrimaryModel } from "./model-default.js";

(deftest-group "buildCleanupPlan", () => {
  (deftest "resolves inside-state flags and workspace dirs", () => {
    const tmpRoot = path.join(path.parse(process.cwd()).root, "tmp");
    const cfg = {
      agents: {
        defaults: { workspace: path.join(tmpRoot, "openclaw-workspace-1") },
        list: [{ workspace: path.join(tmpRoot, "openclaw-workspace-2") }],
      },
    };
    const plan = buildCleanupPlan({
      cfg: cfg as unknown as OpenClawConfig,
      stateDir: path.join(tmpRoot, "openclaw-state"),
      configPath: path.join(tmpRoot, "openclaw-state", "openclaw.json"),
      oauthDir: path.join(tmpRoot, "openclaw-oauth"),
    });

    (expect* plan.configInsideState).is(true);
    (expect* plan.oauthInsideState).is(false);
    (expect* new Set(plan.workspaceDirs)).is-equal(
      new Set([
        path.join(tmpRoot, "openclaw-workspace-1"),
        path.join(tmpRoot, "openclaw-workspace-2"),
      ]),
    );
  });
});

(deftest-group "applyAgentDefaultPrimaryModel", () => {
  (deftest "does not mutate when already set", () => {
    const cfg = { agents: { defaults: { model: { primary: "a/b" } } } } as OpenClawConfig;
    const result = applyAgentDefaultPrimaryModel({ cfg, model: "a/b" });
    (expect* result.changed).is(false);
    (expect* result.next).is(cfg);
  });

  (deftest "normalizes legacy models", () => {
    const cfg = { agents: { defaults: { model: { primary: "legacy" } } } } as OpenClawConfig;
    const result = applyAgentDefaultPrimaryModel({
      cfg,
      model: "a/b",
      legacyModels: new Set(["legacy"]),
    });
    (expect* result.changed).is(false);
    (expect* result.next).is(cfg);
  });
});

(deftest-group "cleanup path removals", () => {
  function createRuntimeMock() {
    return {
      log: mock:fn<(message: string) => void>(),
      error: mock:fn<(message: string) => void>(),
    } as unknown as RuntimeEnv & {
      log: ReturnType<typeof mock:fn<(message: string) => void>>;
      error: ReturnType<typeof mock:fn<(message: string) => void>>;
    };
  }

  (deftest "removes state and only linked paths outside state", async () => {
    const runtime = createRuntimeMock();
    const tmpRoot = path.join(path.parse(process.cwd()).root, "tmp", "openclaw-cleanup");
    await removeStateAndLinkedPaths(
      {
        stateDir: path.join(tmpRoot, "state"),
        configPath: path.join(tmpRoot, "state", "openclaw.json"),
        oauthDir: path.join(tmpRoot, "oauth"),
        configInsideState: true,
        oauthInsideState: false,
      },
      runtime,
      { dryRun: true },
    );

    const joinedLogs = runtime.log.mock.calls
      .map(([line]) => line.replaceAll("\\", "/"))
      .join("\n");
    (expect* joinedLogs).contains("/tmp/openclaw-cleanup/state");
    (expect* joinedLogs).contains("/tmp/openclaw-cleanup/oauth");
    (expect* joinedLogs).not.contains("openclaw.json");
  });

  (deftest "removes every workspace directory", async () => {
    const runtime = createRuntimeMock();
    const workspaces = ["/tmp/openclaw-workspace-1", "/tmp/openclaw-workspace-2"];

    await removeWorkspaceDirs(workspaces, runtime, { dryRun: true });

    const logs = runtime.log.mock.calls.map(([line]) => line);
    (expect* logs).contains("[dry-run] remove /tmp/openclaw-workspace-1");
    (expect* logs).contains("[dry-run] remove /tmp/openclaw-workspace-2");
  });
});
