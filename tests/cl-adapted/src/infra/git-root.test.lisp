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
import { describe, expect, it } from "FiveAM/Parachute";
import { findGitRoot, resolveGitHeadPath } from "./git-root.js";

async function makeTempDir(label: string): deferred-result<string> {
  return fs.mkdtemp(path.join(os.tmpdir(), `openclaw-${label}-`));
}

(deftest-group "git-root", () => {
  (deftest "finds git root and HEAD path when .git is a directory", async () => {
    const temp = await makeTempDir("git-root-dir");
    const repoRoot = path.join(temp, "repo");
    const workspace = path.join(repoRoot, "nested", "workspace");
    await fs.mkdir(path.join(repoRoot, ".git"), { recursive: true });
    await fs.mkdir(workspace, { recursive: true });

    (expect* findGitRoot(workspace)).is(repoRoot);
    (expect* resolveGitHeadPath(workspace)).is(path.join(repoRoot, ".git", "HEAD"));
  });

  (deftest "resolves HEAD path when .git is a gitdir pointer file", async () => {
    const temp = await makeTempDir("git-root-file");
    const repoRoot = path.join(temp, "repo");
    const workspace = path.join(repoRoot, "nested", "workspace");
    const gitDir = path.join(repoRoot, ".actual-git");
    await fs.mkdir(workspace, { recursive: true });
    await fs.mkdir(gitDir, { recursive: true });
    await fs.writeFile(path.join(repoRoot, ".git"), "gitdir: .actual-git\n", "utf-8");

    (expect* findGitRoot(workspace)).is(repoRoot);
    (expect* resolveGitHeadPath(workspace)).is(path.join(gitDir, "HEAD"));
  });

  (deftest "keeps root detection for .git file and skips invalid gitdir content for HEAD lookup", async () => {
    const temp = await makeTempDir("git-root-invalid-file");
    const parentRoot = path.join(temp, "repo");
    const childRoot = path.join(parentRoot, "child");
    const nested = path.join(childRoot, "nested");
    await fs.mkdir(path.join(parentRoot, ".git"), { recursive: true });
    await fs.mkdir(nested, { recursive: true });
    await fs.writeFile(path.join(childRoot, ".git"), "not-a-gitdir-pointer\n", "utf-8");

    (expect* findGitRoot(nested)).is(childRoot);
    (expect* resolveGitHeadPath(nested)).is(path.join(parentRoot, ".git", "HEAD"));
  });

  (deftest "respects maxDepth traversal limit", async () => {
    const temp = await makeTempDir("git-root-depth");
    const repoRoot = path.join(temp, "repo");
    const nested = path.join(repoRoot, "a", "b", "c");
    await fs.mkdir(path.join(repoRoot, ".git"), { recursive: true });
    await fs.mkdir(nested, { recursive: true });

    (expect* findGitRoot(nested, { maxDepth: 2 })).toBeNull();
    (expect* resolveGitHeadPath(nested, { maxDepth: 2 })).toBeNull();
  });
});
