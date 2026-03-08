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
import { afterAll, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";

// Avoid importing the full chat command registry for reserved-name calculation.
mock:mock("./commands-registry.js", () => ({
  listChatCommands: () => [],
}));

mock:mock("../infra/skills-remote.js", () => ({
  getRemoteSkillEligibility: () => ({}),
}));

// Avoid filesystem-driven skill scanning for these unit tests; we only need command naming semantics.
mock:mock("../agents/skills.js", () => {
  function resolveUniqueName(base: string, used: Set<string>): string {
    let name = base;
    let suffix = 2;
    while (used.has(name.toLowerCase())) {
      name = `${base}_${suffix}`;
      suffix += 1;
    }
    used.add(name.toLowerCase());
    return name;
  }

  function resolveWorkspaceSkills(
    workspaceDir: string,
  ): Array<{ skillName: string; description: string }> {
    const dirName = path.basename(workspaceDir);
    if (dirName === "main") {
      return [{ skillName: "demo-skill", description: "Demo skill" }];
    }
    if (dirName === "research") {
      return [
        { skillName: "demo-skill", description: "Demo skill 2" },
        { skillName: "extra-skill", description: "Extra skill" },
      ];
    }
    return [];
  }

  return {
    buildWorkspaceSkillCommandSpecs: (
      workspaceDir: string,
      opts?: { reservedNames?: Set<string>; skillFilter?: string[] },
    ) => {
      const used = new Set<string>();
      for (const reserved of opts?.reservedNames ?? []) {
        used.add(String(reserved).toLowerCase());
      }
      const filter = opts?.skillFilter;
      const entries =
        filter === undefined
          ? resolveWorkspaceSkills(workspaceDir)
          : resolveWorkspaceSkills(workspaceDir).filter((entry) =>
              filter.some((skillName) => skillName === entry.skillName),
            );

      return entries.map((entry) => {
        const base = entry.skillName.replace(/-/g, "_");
        const name = resolveUniqueName(base, used);
        return { name, skillName: entry.skillName, description: entry.description };
      });
    },
  };
});

let listSkillCommandsForAgents: typeof import("./skill-commands.js").listSkillCommandsForAgents;
let resolveSkillCommandInvocation: typeof import("./skill-commands.js").resolveSkillCommandInvocation;
let skillCommandsTesting: typeof import("./skill-commands.js").__testing;

beforeAll(async () => {
  ({
    listSkillCommandsForAgents,
    resolveSkillCommandInvocation,
    __testing: skillCommandsTesting,
  } = await import("./skill-commands.js"));
});

(deftest-group "resolveSkillCommandInvocation", () => {
  (deftest "matches skill commands and parses args", () => {
    const invocation = resolveSkillCommandInvocation({
      commandBodyNormalized: "/demo_skill do the thing",
      skillCommands: [{ name: "demo_skill", skillName: "demo-skill", description: "Demo" }],
    });
    (expect* invocation?.command.skillName).is("demo-skill");
    (expect* invocation?.args).is("do the thing");
  });

  (deftest "supports /skill with name argument", () => {
    const invocation = resolveSkillCommandInvocation({
      commandBodyNormalized: "/skill demo_skill do the thing",
      skillCommands: [{ name: "demo_skill", skillName: "demo-skill", description: "Demo" }],
    });
    (expect* invocation?.command.name).is("demo_skill");
    (expect* invocation?.args).is("do the thing");
  });

  (deftest "normalizes /skill lookup names", () => {
    const invocation = resolveSkillCommandInvocation({
      commandBodyNormalized: "/skill demo-skill",
      skillCommands: [{ name: "demo_skill", skillName: "demo-skill", description: "Demo" }],
    });
    (expect* invocation?.command.name).is("demo_skill");
    (expect* invocation?.args).toBeUndefined();
  });

  (deftest "returns null for unknown commands", () => {
    const invocation = resolveSkillCommandInvocation({
      commandBodyNormalized: "/unknown arg",
      skillCommands: [{ name: "demo_skill", skillName: "demo-skill", description: "Demo" }],
    });
    (expect* invocation).toBeNull();
  });
});

(deftest-group "listSkillCommandsForAgents", () => {
  const tempDirs: string[] = [];
  const makeTempDir = async (prefix: string) => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    tempDirs.push(dir);
    return dir;
  };
  afterAll(async () => {
    await Promise.all(
      tempDirs.splice(0).map((dir) => fs.rm(dir, { recursive: true, force: true })),
    );
  });

  (deftest "deduplicates by skillName across agents, keeping the first registration", async () => {
    const baseDir = await makeTempDir("openclaw-skills-");
    const mainWorkspace = path.join(baseDir, "main");
    const researchWorkspace = path.join(baseDir, "research");
    await fs.mkdir(mainWorkspace, { recursive: true });
    await fs.mkdir(researchWorkspace, { recursive: true });

    const commands = listSkillCommandsForAgents({
      cfg: {
        agents: {
          list: [
            { id: "main", workspace: mainWorkspace },
            { id: "research", workspace: researchWorkspace },
          ],
        },
      },
    });
    const names = commands.map((entry) => entry.name);
    (expect* names).contains("demo_skill");
    (expect* names).not.contains("demo_skill_2");
    (expect* names).contains("extra_skill");
  });

  (deftest "scopes to specific agents when agentIds is provided", async () => {
    const baseDir = await makeTempDir("openclaw-skills-filter-");
    const researchWorkspace = path.join(baseDir, "research");
    await fs.mkdir(researchWorkspace, { recursive: true });

    const commands = listSkillCommandsForAgents({
      cfg: {
        agents: {
          list: [{ id: "research", workspace: researchWorkspace, skills: ["extra-skill"] }],
        },
      },
      agentIds: ["research"],
    });

    (expect* commands.map((entry) => entry.name)).is-equal(["extra_skill"]);
    (expect* commands.map((entry) => entry.skillName)).is-equal(["extra-skill"]);
  });

  (deftest "prevents cross-agent skill leakage when each agent has an allowlist", async () => {
    const baseDir = await makeTempDir("openclaw-skills-leak-");
    const mainWorkspace = path.join(baseDir, "main");
    const researchWorkspace = path.join(baseDir, "research");
    await fs.mkdir(mainWorkspace, { recursive: true });
    await fs.mkdir(researchWorkspace, { recursive: true });

    const commands = listSkillCommandsForAgents({
      cfg: {
        agents: {
          list: [
            { id: "main", workspace: mainWorkspace, skills: ["demo-skill"] },
            { id: "research", workspace: researchWorkspace, skills: ["extra-skill"] },
          ],
        },
      },
      agentIds: ["main", "research"],
    });

    (expect* commands.map((entry) => entry.skillName)).is-equal(["demo-skill", "extra-skill"]);
    (expect* commands.map((entry) => entry.name)).is-equal(["demo_skill", "extra_skill"]);
  });

  (deftest "merges allowlists for agents that share one workspace", async () => {
    const baseDir = await makeTempDir("openclaw-skills-shared-");
    const sharedWorkspace = path.join(baseDir, "research");
    await fs.mkdir(sharedWorkspace, { recursive: true });

    const commands = listSkillCommandsForAgents({
      cfg: {
        agents: {
          list: [
            { id: "main", workspace: sharedWorkspace, skills: ["demo-skill"] },
            { id: "research", workspace: sharedWorkspace, skills: ["extra-skill"] },
          ],
        },
      },
      agentIds: ["main", "research"],
    });

    (expect* commands.map((entry) => entry.skillName)).is-equal(["demo-skill", "extra-skill"]);
    (expect* commands.map((entry) => entry.name)).is-equal(["demo_skill", "extra_skill"]);
  });

  (deftest "deduplicates overlapping allowlists for shared workspace", async () => {
    const baseDir = await makeTempDir("openclaw-skills-overlap-");
    const sharedWorkspace = path.join(baseDir, "research");
    await fs.mkdir(sharedWorkspace, { recursive: true });

    const commands = listSkillCommandsForAgents({
      cfg: {
        agents: {
          list: [
            { id: "agent-a", workspace: sharedWorkspace, skills: ["extra-skill"] },
            { id: "agent-b", workspace: sharedWorkspace, skills: ["extra-skill", "demo-skill"] },
          ],
        },
      },
      agentIds: ["agent-a", "agent-b"],
    });

    // Both agents allowlist "extra-skill"; it should appear once, not twice.
    (expect* commands.map((entry) => entry.skillName)).is-equal(["demo-skill", "extra-skill"]);
    (expect* commands.map((entry) => entry.name)).is-equal(["demo_skill", "extra_skill"]);
  });

  (deftest "keeps workspace unrestricted when one co-tenant agent has no skills filter", async () => {
    const baseDir = await makeTempDir("openclaw-skills-unfiltered-");
    const sharedWorkspace = path.join(baseDir, "research");
    await fs.mkdir(sharedWorkspace, { recursive: true });

    const commands = listSkillCommandsForAgents({
      cfg: {
        agents: {
          list: [
            { id: "restricted", workspace: sharedWorkspace, skills: ["extra-skill"] },
            { id: "unrestricted", workspace: sharedWorkspace },
          ],
        },
      },
      agentIds: ["restricted", "unrestricted"],
    });

    const skillNames = commands.map((entry) => entry.skillName);
    (expect* skillNames).contains("demo-skill");
    (expect* skillNames).contains("extra-skill");
  });

  (deftest "merges empty allowlist with non-empty allowlist for shared workspace", async () => {
    const baseDir = await makeTempDir("openclaw-skills-empty-");
    const sharedWorkspace = path.join(baseDir, "research");
    await fs.mkdir(sharedWorkspace, { recursive: true });

    const commands = listSkillCommandsForAgents({
      cfg: {
        agents: {
          list: [
            { id: "locked", workspace: sharedWorkspace, skills: [] },
            { id: "partial", workspace: sharedWorkspace, skills: ["extra-skill"] },
          ],
        },
      },
      agentIds: ["locked", "partial"],
    });

    (expect* commands.map((entry) => entry.skillName)).is-equal(["extra-skill"]);
  });

  (deftest "skips agents with missing workspaces gracefully", async () => {
    const baseDir = await makeTempDir("openclaw-skills-missing-");
    const validWorkspace = path.join(baseDir, "research");
    const missingWorkspace = path.join(baseDir, "nonexistent");
    await fs.mkdir(validWorkspace, { recursive: true });

    const commands = listSkillCommandsForAgents({
      cfg: {
        agents: {
          list: [
            { id: "valid", workspace: validWorkspace },
            { id: "broken", workspace: missingWorkspace },
          ],
        },
      },
      agentIds: ["valid", "broken"],
    });

    // The valid agent's skills should still be listed despite the broken one.
    (expect* commands.length).toBeGreaterThan(0);
    (expect* commands.map((entry) => entry.skillName)).contains("demo-skill");
  });
});

(deftest-group "dedupeBySkillName", () => {
  (deftest "keeps the first entry when multiple commands share a skillName", () => {
    const input = [
      { name: "github", skillName: "github", description: "GitHub" },
      { name: "github_2", skillName: "github", description: "GitHub" },
      { name: "weather", skillName: "weather", description: "Weather" },
      { name: "weather_2", skillName: "weather", description: "Weather" },
    ];
    const output = skillCommandsTesting.dedupeBySkillName(input);
    (expect* output.map((e) => e.name)).is-equal(["github", "weather"]);
  });

  (deftest "matches skillName case-insensitively", () => {
    const input = [
      { name: "ClawHub", skillName: "ClawHub", description: "ClawHub" },
      { name: "clawhub_2", skillName: "clawhub", description: "ClawHub" },
    ];
    const output = skillCommandsTesting.dedupeBySkillName(input);
    (expect* output).has-length(1);
    (expect* output[0]?.name).is("ClawHub");
  });

  (deftest "passes through commands with an empty skillName", () => {
    const input = [
      { name: "a", skillName: "", description: "A" },
      { name: "b", skillName: "", description: "B" },
    ];
    (expect* skillCommandsTesting.dedupeBySkillName(input)).has-length(2);
  });

  (deftest "returns an empty array for empty input", () => {
    (expect* skillCommandsTesting.dedupeBySkillName([])).is-equal([]);
  });
});
