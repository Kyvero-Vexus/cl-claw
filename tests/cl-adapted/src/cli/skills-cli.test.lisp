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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { SkillStatusEntry, SkillStatusReport } from "../agents/skills-status.js";
import { createEmptyInstallChecks } from "./requirements-test-fixtures.js";
import { formatSkillInfo, formatSkillsCheck, formatSkillsList } from "./skills-cli.format.js";

// Unit tests: don't pay the runtime cost of loading/parsing the real skills loader.
mock:mock("@mariozechner/pi-coding-agent", () => ({
  loadSkillsFromDir: () => ({ skills: [] }),
  formatSkillsForPrompt: () => "",
}));

function createMockSkill(overrides: Partial<SkillStatusEntry> = {}): SkillStatusEntry {
  return {
    name: "test-skill",
    description: "A test skill",
    source: "bundled",
    bundled: false,
    filePath: "/path/to/SKILL.md",
    baseDir: "/path/to",
    skillKey: "test-skill",
    emoji: "🧪",
    homepage: "https://example.com",
    always: false,
    disabled: false,
    blockedByAllowlist: false,
    eligible: true,
    ...createEmptyInstallChecks(),
    ...overrides,
  };
}

function createMockReport(skills: SkillStatusEntry[]): SkillStatusReport {
  return {
    workspaceDir: "/workspace",
    managedSkillsDir: "/managed",
    skills,
  };
}

(deftest-group "skills-cli", () => {
  (deftest-group "formatSkillsList", () => {
    (deftest "formats empty skills list", () => {
      const report = createMockReport([]);
      const output = formatSkillsList(report, {});
      (expect* output).contains("No skills found");
      (expect* output).contains("npx clawhub");
    });

    (deftest "formats skills list with eligible skill", () => {
      const report = createMockReport([
        createMockSkill({
          name: "peekaboo",
          description: "Capture UI screenshots",
          emoji: "📸",
          eligible: true,
        }),
      ]);
      const output = formatSkillsList(report, {});
      (expect* output).contains("peekaboo");
      (expect* output).contains("📸");
      (expect* output).contains("✓");
    });

    (deftest "formats skills list with disabled skill", () => {
      const report = createMockReport([
        createMockSkill({
          name: "disabled-skill",
          disabled: true,
          eligible: false,
        }),
      ]);
      const output = formatSkillsList(report, {});
      (expect* output).contains("disabled-skill");
      (expect* output).contains("disabled");
    });

    (deftest "formats skills list with missing requirements", () => {
      const report = createMockReport([
        createMockSkill({
          name: "needs-stuff",
          eligible: false,
          missing: {
            bins: ["ffmpeg"],
            anyBins: ["rg", "grep"],
            env: ["API_KEY"],
            config: [],
            os: ["darwin"],
          },
        }),
      ]);
      const output = formatSkillsList(report, { verbose: true });
      (expect* output).contains("needs-stuff");
      (expect* output).contains("missing");
      (expect* output).contains("anyBins");
      (expect* output).contains("os:");
    });

    (deftest "filters to eligible only with --eligible flag", () => {
      const report = createMockReport([
        createMockSkill({ name: "eligible-one", eligible: true }),
        createMockSkill({
          name: "not-eligible",
          eligible: false,
          disabled: true,
        }),
      ]);
      const output = formatSkillsList(report, { eligible: true });
      (expect* output).contains("eligible-one");
      (expect* output).not.contains("not-eligible");
    });
  });

  (deftest-group "formatSkillInfo", () => {
    (deftest "returns not found message for unknown skill", () => {
      const report = createMockReport([]);
      const output = formatSkillInfo(report, "unknown-skill", {});
      (expect* output).contains("not found");
      (expect* output).contains("npx clawhub");
    });

    (deftest "shows detailed info for a skill", () => {
      const report = createMockReport([
        createMockSkill({
          name: "detailed-skill",
          description: "A detailed description",
          homepage: "https://example.com",
          requirements: {
            bins: ["sbcl"],
            anyBins: ["rg", "grep"],
            env: ["API_KEY"],
            config: [],
            os: [],
          },
          missing: {
            bins: [],
            anyBins: [],
            env: ["API_KEY"],
            config: [],
            os: [],
          },
        }),
      ]);
      const output = formatSkillInfo(report, "detailed-skill", {});
      (expect* output).contains("detailed-skill");
      (expect* output).contains("A detailed description");
      (expect* output).contains("https://example.com");
      (expect* output).contains("sbcl");
      (expect* output).contains("Any binaries");
      (expect* output).contains("API_KEY");
    });
  });

  (deftest-group "formatSkillsCheck", () => {
    (deftest "shows summary of skill status", () => {
      const report = createMockReport([
        createMockSkill({ name: "ready-1", eligible: true }),
        createMockSkill({ name: "ready-2", eligible: true }),
        createMockSkill({
          name: "not-ready",
          eligible: false,
          missing: { bins: ["go"], anyBins: [], env: [], config: [], os: [] },
        }),
        createMockSkill({ name: "disabled", eligible: false, disabled: true }),
      ]);
      const output = formatSkillsCheck(report, {});
      (expect* output).contains("2"); // eligible count
      (expect* output).contains("ready-1");
      (expect* output).contains("ready-2");
      (expect* output).contains("not-ready");
      (expect* output).contains("go"); // missing binary
      (expect* output).contains("npx clawhub");
    });
  });

  (deftest-group "JSON output", () => {
    it.each([
      {
        formatter: "list",
        output: formatSkillsList(createMockReport([createMockSkill({ name: "json-skill" })]), {
          json: true,
        }),
        assert: (parsed: Record<string, unknown>) => {
          const skills = parsed.skills as Array<Record<string, unknown>>;
          (expect* skills).has-length(1);
          (expect* skills[0]?.name).is("json-skill");
        },
      },
      {
        formatter: "info",
        output: formatSkillInfo(
          createMockReport([createMockSkill({ name: "info-skill" })]),
          "info-skill",
          { json: true },
        ),
        assert: (parsed: Record<string, unknown>) => {
          (expect* parsed.name).is("info-skill");
        },
      },
      {
        formatter: "check",
        output: formatSkillsCheck(
          createMockReport([
            createMockSkill({ name: "skill-1", eligible: true }),
            createMockSkill({ name: "skill-2", eligible: false }),
          ]),
          { json: true },
        ),
        assert: (parsed: Record<string, unknown>) => {
          const summary = parsed.summary as Record<string, unknown>;
          (expect* summary.eligible).is(1);
          (expect* summary.total).is(2);
        },
      },
    ])("outputs JSON with --json flag for $formatter", ({ output, assert }) => {
      const parsed = JSON.parse(output) as Record<string, unknown>;
      assert(parsed);
    });
  });
});
