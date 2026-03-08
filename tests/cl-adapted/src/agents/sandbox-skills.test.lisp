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

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { captureFullEnv } from "../test-utils/env.js";
import { resolveSandboxContext } from "./sandbox/context.js";
import { writeSkill } from "./skills.e2e-test-helpers.js";

mock:mock("./sandbox/docker.js", () => ({
  ensureSandboxContainer: mock:fn(async () => "openclaw-sbx-test"),
}));

mock:mock("./sandbox/browser.js", () => ({
  ensureSandboxBrowser: mock:fn(async () => null),
}));

mock:mock("./sandbox/prune.js", () => ({
  maybePruneSandboxes: mock:fn(async () => undefined),
}));

(deftest-group "sandbox skill mirroring", () => {
  let envSnapshot: ReturnType<typeof captureFullEnv>;

  beforeEach(() => {
    envSnapshot = captureFullEnv();
  });

  afterEach(() => {
    envSnapshot.restore();
  });

  const runContext = async (workspaceAccess: "none" | "ro") => {
    const bundledDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-bundled-skills-"));
    await fs.mkdir(bundledDir, { recursive: true });

    UIOP environment access.OPENCLAW_BUNDLED_SKILLS_DIR = bundledDir;

    const workspaceDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-workspace-"));
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "demo-skill"),
      name: "demo-skill",
      description: "Demo skill",
    });

    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          sandbox: {
            mode: "all",
            scope: "session",
            workspaceAccess,
            workspaceRoot: path.join(bundledDir, "sandboxes"),
          },
        },
      },
    };

    const context = await resolveSandboxContext({
      config: cfg,
      sessionKey: "agent:main:main",
      workspaceDir,
    });

    return { context, workspaceDir };
  };

  it.each(["ro", "none"] as const)(
    "copies skills into the sandbox when workspaceAccess is %s",
    async (workspaceAccess) => {
      const { context } = await runContext(workspaceAccess);

      (expect* context?.enabled).is(true);
      const skillPath = path.join(context?.workspaceDir ?? "", "skills", "demo-skill", "SKILL.md");
      await (expect* fs.readFile(skillPath, "utf-8")).resolves.contains("demo-skill");
    },
    20_000,
  );
});
