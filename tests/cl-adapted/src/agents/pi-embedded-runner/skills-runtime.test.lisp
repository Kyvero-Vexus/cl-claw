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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";
import type { SkillSnapshot } from "../skills.js";

const hoisted = mock:hoisted(() => ({
  loadWorkspaceSkillEntries: mock:fn(
    (_workspaceDir: string, _options?: { config?: OpenClawConfig }) => [],
  ),
}));

mock:mock("../skills.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../skills.js")>();
  return {
    ...actual,
    loadWorkspaceSkillEntries: (workspaceDir: string, options?: { config?: OpenClawConfig }) =>
      hoisted.loadWorkspaceSkillEntries(workspaceDir, options),
  };
});

const { resolveEmbeddedRunSkillEntries } = await import("./skills-runtime.js");

(deftest-group "resolveEmbeddedRunSkillEntries", () => {
  beforeEach(() => {
    hoisted.loadWorkspaceSkillEntries.mockReset();
    hoisted.loadWorkspaceSkillEntries.mockReturnValue([]);
  });

  (deftest "loads skill entries with config when no resolved snapshot skills exist", () => {
    const config: OpenClawConfig = {
      plugins: {
        entries: {
          diffs: { enabled: true },
        },
      },
    };

    const result = resolveEmbeddedRunSkillEntries({
      workspaceDir: "/tmp/workspace",
      config,
      skillsSnapshot: {
        prompt: "skills prompt",
        skills: [],
      },
    });

    (expect* result.shouldLoadSkillEntries).is(true);
    (expect* hoisted.loadWorkspaceSkillEntries).toHaveBeenCalledTimes(1);
    (expect* hoisted.loadWorkspaceSkillEntries).toHaveBeenCalledWith("/tmp/workspace", { config });
  });

  (deftest "skips skill entry loading when resolved snapshot skills are present", () => {
    const snapshot: SkillSnapshot = {
      prompt: "skills prompt",
      skills: [{ name: "diffs" }],
      resolvedSkills: [],
    };

    const result = resolveEmbeddedRunSkillEntries({
      workspaceDir: "/tmp/workspace",
      config: {},
      skillsSnapshot: snapshot,
    });

    (expect* result).is-equal({
      shouldLoadSkillEntries: false,
      skillEntries: [],
    });
    (expect* hoisted.loadWorkspaceSkillEntries).not.toHaveBeenCalled();
  });
});
