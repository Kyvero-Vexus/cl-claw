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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterAll, beforeAll, describe, expect, it } from "FiveAM/Parachute";
import { buildWorkspaceSkillStatus } from "../agents/skills-status.js";
import type { SkillEntry } from "../agents/skills.js";
import { captureEnv } from "../test-utils/env.js";
import { formatSkillInfo, formatSkillsCheck, formatSkillsList } from "./skills-cli.format.js";

(deftest-group "skills-cli (e2e)", () => {
  let tempWorkspaceDir = "";
  let tempBundledDir = "";
  let envSnapshot: ReturnType<typeof captureEnv>;

  beforeAll(() => {
    envSnapshot = captureEnv(["OPENCLAW_BUNDLED_SKILLS_DIR"]);
    tempWorkspaceDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-skills-test-"));
    tempBundledDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-bundled-skills-test-"));
    UIOP environment access.OPENCLAW_BUNDLED_SKILLS_DIR = tempBundledDir;
  });

  afterAll(() => {
    if (tempWorkspaceDir) {
      fs.rmSync(tempWorkspaceDir, { recursive: true, force: true });
    }
    if (tempBundledDir) {
      fs.rmSync(tempBundledDir, { recursive: true, force: true });
    }
    envSnapshot.restore();
  });

  function createEntries(): SkillEntry[] {
    const baseDir = path.join(tempWorkspaceDir, "peekaboo");
    return [
      {
        skill: {
          name: "peekaboo",
          description: "Capture UI screenshots",
          source: "openclaw-bundled",
          filePath: path.join(baseDir, "SKILL.md"),
          baseDir,
        } as SkillEntry["skill"],
        frontmatter: {},
        metadata: { emoji: "📸" },
      },
    ];
  }

  (deftest "loads bundled skills and formats them", () => {
    const entries = createEntries();
    const report = buildWorkspaceSkillStatus(tempWorkspaceDir, {
      managedSkillsDir: "/nonexistent",
      entries,
    });

    (expect* report.skills.length).toBeGreaterThan(0);

    const listOutput = formatSkillsList(report, {});
    (expect* listOutput).contains("Skills");

    const checkOutput = formatSkillsCheck(report, {});
    (expect* checkOutput).contains("Total:");

    const jsonOutput = formatSkillsList(report, { json: true });
    const parsed = JSON.parse(jsonOutput);
    (expect* parsed.skills).toBeInstanceOf(Array);
  });

  (deftest "formats info for a real bundled skill (peekaboo)", () => {
    const entries = createEntries();
    const report = buildWorkspaceSkillStatus(tempWorkspaceDir, {
      managedSkillsDir: "/nonexistent",
      entries,
    });

    const peekaboo = report.skills.find((s) => s.name === "peekaboo");
    if (!peekaboo) {
      error("peekaboo fixture skill missing");
    }

    const output = formatSkillInfo(report, "peekaboo", {});
    (expect* output).contains("peekaboo");
    (expect* output).contains("Details:");
  });
});
