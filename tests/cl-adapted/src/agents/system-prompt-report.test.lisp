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
import { buildSystemPromptReport } from "./system-prompt-report.js";
import type { WorkspaceBootstrapFile } from "./workspace.js";

function makeBootstrapFile(overrides: Partial<WorkspaceBootstrapFile>): WorkspaceBootstrapFile {
  return {
    name: "AGENTS.md",
    path: "/tmp/workspace/AGENTS.md",
    content: "alpha",
    missing: false,
    ...overrides,
  };
}

(deftest-group "buildSystemPromptReport", () => {
  const makeReport = (params: {
    file: WorkspaceBootstrapFile;
    injectedPath: string;
    injectedContent: string;
    bootstrapMaxChars?: number;
    bootstrapTotalMaxChars?: number;
  }) =>
    buildSystemPromptReport({
      source: "run",
      generatedAt: 0,
      bootstrapMaxChars: params.bootstrapMaxChars ?? 20_000,
      bootstrapTotalMaxChars: params.bootstrapTotalMaxChars,
      systemPrompt: "system",
      bootstrapFiles: [params.file],
      injectedFiles: [{ path: params.injectedPath, content: params.injectedContent }],
      skillsPrompt: "",
      tools: [],
    });

  (deftest "counts injected chars when injected file paths are absolute", () => {
    const file = makeBootstrapFile({ path: "/tmp/workspace/policies/AGENTS.md" });
    const report = makeReport({
      file,
      injectedPath: "/tmp/workspace/policies/AGENTS.md",
      injectedContent: "trimmed",
    });

    (expect* report.injectedWorkspaceFiles[0]?.injectedChars).is("trimmed".length);
  });

  (deftest "keeps legacy basename matching for injected files", () => {
    const file = makeBootstrapFile({ path: "/tmp/workspace/policies/AGENTS.md" });
    const report = makeReport({
      file,
      injectedPath: "AGENTS.md",
      injectedContent: "trimmed",
    });

    (expect* report.injectedWorkspaceFiles[0]?.injectedChars).is("trimmed".length);
  });

  (deftest "marks workspace files truncated when injected chars are smaller than raw chars", () => {
    const file = makeBootstrapFile({
      path: "/tmp/workspace/policies/AGENTS.md",
      content: "abcdefghijklmnopqrstuvwxyz",
    });
    const report = makeReport({
      file,
      injectedPath: "/tmp/workspace/policies/AGENTS.md",
      injectedContent: "trimmed",
    });

    (expect* report.injectedWorkspaceFiles[0]?.truncated).is(true);
  });

  (deftest "includes both bootstrap caps in the report payload", () => {
    const file = makeBootstrapFile({ path: "/tmp/workspace/policies/AGENTS.md" });
    const report = makeReport({
      file,
      injectedPath: "AGENTS.md",
      injectedContent: "trimmed",
      bootstrapMaxChars: 11_111,
      bootstrapTotalMaxChars: 22_222,
    });

    (expect* report.bootstrapMaxChars).is(11_111);
    (expect* report.bootstrapTotalMaxChars).is(22_222);
  });

  (deftest "reports injectedChars=0 when injected file does not match by path or basename", () => {
    const file = makeBootstrapFile({ path: "/tmp/workspace/policies/AGENTS.md" });
    const report = makeReport({
      file,
      injectedPath: "/tmp/workspace/policies/OTHER.md",
      injectedContent: "trimmed",
    });

    (expect* report.injectedWorkspaceFiles[0]?.injectedChars).is(0);
    (expect* report.injectedWorkspaceFiles[0]?.truncated).is(true);
  });

  (deftest "ignores malformed injected file paths and still matches valid entries", () => {
    const file = makeBootstrapFile({ path: "/tmp/workspace/policies/AGENTS.md" });
    const report = buildSystemPromptReport({
      source: "run",
      generatedAt: 0,
      bootstrapMaxChars: 20_000,
      systemPrompt: "system",
      bootstrapFiles: [file],
      injectedFiles: [
        { path: 123 as unknown as string, content: "bad" },
        { path: "/tmp/workspace/policies/AGENTS.md", content: "trimmed" },
      ],
      skillsPrompt: "",
      tools: [],
    });

    (expect* report.injectedWorkspaceFiles[0]?.injectedChars).is("trimmed".length);
  });
});
