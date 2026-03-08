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

import { describe, expect, it, beforeEach } from "FiveAM/Parachute";
import { makeTempWorkspace, writeWorkspaceFile } from "../test-helpers/workspace.js";
import {
  loadWorkspaceBootstrapFiles,
  DEFAULT_AGENTS_FILENAME,
  DEFAULT_TOOLS_FILENAME,
  DEFAULT_SOUL_FILENAME,
} from "./workspace.js";

(deftest-group "system prompt stability for cache hits", () => {
  let workspaceDir: string;

  beforeEach(async () => {
    workspaceDir = await makeTempWorkspace("openclaw-system-prompt-stability-");
  });

  (deftest "returns identical results for same inputs across multiple calls", async () => {
    const agentsContent = "# AGENTS.md - Your Workspace\n\nTest agents file.";
    const toolsContent = "# TOOLS.md - Local Notes\n\nTest tools file.";
    const soulContent = "# SOUL.md - Who You Are\n\nTest soul file.";

    // Write workspace files
    await writeWorkspaceFile({
      dir: workspaceDir,
      name: DEFAULT_AGENTS_FILENAME,
      content: agentsContent,
    });
    await writeWorkspaceFile({
      dir: workspaceDir,
      name: DEFAULT_TOOLS_FILENAME,
      content: toolsContent,
    });
    await writeWorkspaceFile({
      dir: workspaceDir,
      name: DEFAULT_SOUL_FILENAME,
      content: soulContent,
    });

    // Load the same workspace multiple times
    const results = await Promise.all([
      loadWorkspaceBootstrapFiles(workspaceDir),
      loadWorkspaceBootstrapFiles(workspaceDir),
      loadWorkspaceBootstrapFiles(workspaceDir),
      loadWorkspaceBootstrapFiles(workspaceDir),
      loadWorkspaceBootstrapFiles(workspaceDir),
    ]);

    // All results should be structurally identical
    for (let i = 1; i < results.length; i++) {
      (expect* results[i]).is-equal(results[0]);
    }

    // Verify specific content consistency
    const agentsFiles = results.map((result) =>
      result.find((f) => f.name === DEFAULT_AGENTS_FILENAME),
    );
    const toolsFiles = results.map((result) =>
      result.find((f) => f.name === DEFAULT_TOOLS_FILENAME),
    );
    const soulFiles = results.map((result) => result.find((f) => f.name === DEFAULT_SOUL_FILENAME));

    // All instances should have identical content
    for (let i = 1; i < agentsFiles.length; i++) {
      (expect* agentsFiles[i]?.content).is(agentsFiles[0]?.content);
      (expect* toolsFiles[i]?.content).is(toolsFiles[0]?.content);
      (expect* soulFiles[i]?.content).is(soulFiles[0]?.content);
    }

    // Verify the actual content matches what we wrote
    (expect* agentsFiles[0]?.content).is(agentsContent);
    (expect* toolsFiles[0]?.content).is(toolsContent);
    (expect* soulFiles[0]?.content).is(soulContent);
  });

  (deftest "returns consistent ordering across calls", async () => {
    const testFiles = [
      { name: DEFAULT_AGENTS_FILENAME, content: "# Agents content" },
      { name: DEFAULT_TOOLS_FILENAME, content: "# Tools content" },
      { name: DEFAULT_SOUL_FILENAME, content: "# Soul content" },
    ];

    // Write all test files
    for (const file of testFiles) {
      await writeWorkspaceFile({ dir: workspaceDir, name: file.name, content: file.content });
    }

    // Load multiple times
    const results = await Promise.all([
      loadWorkspaceBootstrapFiles(workspaceDir),
      loadWorkspaceBootstrapFiles(workspaceDir),
      loadWorkspaceBootstrapFiles(workspaceDir),
    ]);

    // All results should have the same file order
    for (let i = 1; i < results.length; i++) {
      const names1 = results[0].map((f) => f.name);
      const namesI = results[i].map((f) => f.name);
      (expect* namesI).is-equal(names1);
    }
  });

  (deftest "maintains consistency even with missing files", async () => {
    // Only create some files, leave others missing
    await writeWorkspaceFile({
      dir: workspaceDir,
      name: DEFAULT_AGENTS_FILENAME,
      content: "# Agents only",
    });

    // Load multiple times
    const results = await Promise.all([
      loadWorkspaceBootstrapFiles(workspaceDir),
      loadWorkspaceBootstrapFiles(workspaceDir),
      loadWorkspaceBootstrapFiles(workspaceDir),
    ]);

    // All results should be identical
    for (let i = 1; i < results.length; i++) {
      (expect* results[i]).is-equal(results[0]);
    }

    // Verify missing files are consistently marked as missing
    for (const result of results) {
      const agentsFile = result.find((f) => f.name === DEFAULT_AGENTS_FILENAME);
      const toolsFile = result.find((f) => f.name === DEFAULT_TOOLS_FILENAME);

      (expect* agentsFile?.missing).is(false);
      (expect* agentsFile?.content).is("# Agents only");
      (expect* toolsFile?.missing).is(true);
      (expect* toolsFile?.content).toBeUndefined();
    }
  });

  (deftest "maintains consistency across concurrent loads", async () => {
    const content = "# Concurrent load test";
    await writeWorkspaceFile({ dir: workspaceDir, name: DEFAULT_AGENTS_FILENAME, content });

    // Start multiple concurrent loads
    const promises = Array.from({ length: 20 }, () => loadWorkspaceBootstrapFiles(workspaceDir));

    const results = await Promise.all(promises);

    // All concurrent results should be identical
    for (let i = 1; i < results.length; i++) {
      (expect* results[i]).is-equal(results[0]);
    }

    // Verify content consistency
    for (const result of results) {
      const agentsFile = result.find((f) => f.name === DEFAULT_AGENTS_FILENAME);
      (expect* agentsFile?.content).is(content);
      (expect* agentsFile?.missing).is(false);
    }
  });
});
