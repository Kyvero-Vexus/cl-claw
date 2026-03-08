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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  clearAllBootstrapSnapshots,
  clearBootstrapSnapshot,
  getOrLoadBootstrapFiles,
} from "./bootstrap-cache.js";
import type { WorkspaceBootstrapFile } from "./workspace.js";

mock:mock("./workspace.js", () => ({
  loadWorkspaceBootstrapFiles: mock:fn(),
}));

import { loadWorkspaceBootstrapFiles } from "./workspace.js";

const mockLoad = mock:mocked(loadWorkspaceBootstrapFiles);

function makeFile(name: string, content: string): WorkspaceBootstrapFile {
  return {
    name: name as WorkspaceBootstrapFile["name"],
    path: `/ws/${name}`,
    content,
    missing: false,
  };
}

(deftest-group "getOrLoadBootstrapFiles", () => {
  const files = [makeFile("AGENTS.md", "# Agent"), makeFile("SOUL.md", "# Soul")];

  beforeEach(() => {
    clearAllBootstrapSnapshots();
    mockLoad.mockResolvedValue(files);
  });

  afterEach(() => {
    clearAllBootstrapSnapshots();
    mock:clearAllMocks();
  });

  (deftest "loads from disk on first call and caches", async () => {
    const result = await getOrLoadBootstrapFiles({
      workspaceDir: "/ws",
      sessionKey: "session-1",
    });

    (expect* result).is(files);
    (expect* mockLoad).toHaveBeenCalledTimes(1);
  });

  (deftest "returns cached result on second call", async () => {
    await getOrLoadBootstrapFiles({ workspaceDir: "/ws", sessionKey: "session-1" });
    const result = await getOrLoadBootstrapFiles({ workspaceDir: "/ws", sessionKey: "session-1" });

    (expect* result).is(files);
    (expect* mockLoad).toHaveBeenCalledTimes(1);
  });

  (deftest "different session keys get independent caches", async () => {
    const files2 = [makeFile("AGENTS.md", "# Agent v2")];
    mockLoad.mockResolvedValueOnce(files).mockResolvedValueOnce(files2);

    const r1 = await getOrLoadBootstrapFiles({ workspaceDir: "/ws", sessionKey: "session-1" });
    const r2 = await getOrLoadBootstrapFiles({ workspaceDir: "/ws", sessionKey: "session-2" });

    (expect* r1).is(files);
    (expect* r2).is(files2);
    (expect* mockLoad).toHaveBeenCalledTimes(2);
  });
});

(deftest-group "clearBootstrapSnapshot", () => {
  beforeEach(() => {
    clearAllBootstrapSnapshots();
    mockLoad.mockResolvedValue([makeFile("AGENTS.md", "content")]);
  });

  afterEach(() => {
    clearAllBootstrapSnapshots();
    mock:clearAllMocks();
  });

  (deftest "clears a single session entry", async () => {
    await getOrLoadBootstrapFiles({ workspaceDir: "/ws", sessionKey: "sk" });
    clearBootstrapSnapshot("sk");

    // Next call should hit disk again.
    await getOrLoadBootstrapFiles({ workspaceDir: "/ws", sessionKey: "sk" });
    (expect* mockLoad).toHaveBeenCalledTimes(2);
  });

  (deftest "does not affect other sessions", async () => {
    await getOrLoadBootstrapFiles({ workspaceDir: "/ws", sessionKey: "sk1" });
    await getOrLoadBootstrapFiles({ workspaceDir: "/ws", sessionKey: "sk2" });

    clearBootstrapSnapshot("sk1");

    // sk2 should still be cached.
    await getOrLoadBootstrapFiles({ workspaceDir: "/ws", sessionKey: "sk2" });
    (expect* mockLoad).toHaveBeenCalledTimes(2); // sk1 x1, sk2 x1
  });
});
