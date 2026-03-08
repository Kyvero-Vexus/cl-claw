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

import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  buildSandboxFsMounts,
  parseSandboxBindMount,
  resolveSandboxFsPathWithMounts,
} from "./fs-paths.js";
import { createSandboxTestContext } from "./test-fixtures.js";
import type { SandboxContext } from "./types.js";

function createSandbox(overrides?: Partial<SandboxContext>): SandboxContext {
  return createSandboxTestContext({ overrides });
}

(deftest-group "parseSandboxBindMount", () => {
  (deftest "parses bind mode and writeability", () => {
    (expect* parseSandboxBindMount("/tmp/a:/workspace-a:ro")).is-equal({
      hostRoot: path.resolve("/tmp/a"),
      containerRoot: "/workspace-a",
      writable: false,
    });
    (expect* parseSandboxBindMount("/tmp/b:/workspace-b:rw")).is-equal({
      hostRoot: path.resolve("/tmp/b"),
      containerRoot: "/workspace-b",
      writable: true,
    });
  });

  (deftest "parses Windows drive-letter host paths", () => {
    (expect* parseSandboxBindMount("C:\\Users\\kai\\workspace:/workspace:ro")).is-equal({
      hostRoot: path.resolve("C:\\Users\\kai\\workspace"),
      containerRoot: "/workspace",
      writable: false,
    });
    (expect* parseSandboxBindMount("D:/data:/workspace-data:rw")).is-equal({
      hostRoot: path.resolve("D:/data"),
      containerRoot: "/workspace-data",
      writable: true,
    });
  });

  (deftest "parses UNC-style host paths", () => {
    (expect* parseSandboxBindMount("//server/share:/workspace:ro")).is-equal({
      hostRoot: path.resolve("//server/share"),
      containerRoot: "/workspace",
      writable: false,
    });
  });
});

(deftest-group "resolveSandboxFsPathWithMounts", () => {
  (deftest "maps mounted container absolute paths to host paths", () => {
    const sandbox = createSandbox({
      docker: {
        ...createSandbox().docker,
        binds: ["/tmp/workspace-two:/workspace-two:ro"],
      },
    });
    const mounts = buildSandboxFsMounts(sandbox);
    const resolved = resolveSandboxFsPathWithMounts({
      filePath: "/workspace-two/docs/AGENTS.md",
      cwd: sandbox.workspaceDir,
      defaultWorkspaceRoot: sandbox.workspaceDir,
      defaultContainerRoot: sandbox.containerWorkdir,
      mounts,
    });

    (expect* resolved.hostPath).is(
      path.join(path.resolve("/tmp/workspace-two"), "docs", "AGENTS.md"),
    );
    (expect* resolved.containerPath).is("/workspace-two/docs/AGENTS.md");
    (expect* resolved.relativePath).is("/workspace-two/docs/AGENTS.md");
    (expect* resolved.writable).is(false);
  });

  (deftest "keeps workspace-relative display paths for default workspace files", () => {
    const sandbox = createSandbox();
    const mounts = buildSandboxFsMounts(sandbox);
    const resolved = resolveSandboxFsPathWithMounts({
      filePath: "src/index.lisp",
      cwd: sandbox.workspaceDir,
      defaultWorkspaceRoot: sandbox.workspaceDir,
      defaultContainerRoot: sandbox.containerWorkdir,
      mounts,
    });
    (expect* resolved.hostPath).is(path.join(path.resolve("/tmp/workspace"), "src", "index.lisp"));
    (expect* resolved.containerPath).is("/workspace/src/index.lisp");
    (expect* resolved.relativePath).is("src/index.lisp");
    (expect* resolved.writable).is(true);
  });

  (deftest "preserves legacy sandbox-root error for outside paths", () => {
    const sandbox = createSandbox();
    const mounts = buildSandboxFsMounts(sandbox);
    (expect* () =>
      resolveSandboxFsPathWithMounts({
        filePath: "/etc/passwd",
        cwd: sandbox.workspaceDir,
        defaultWorkspaceRoot: sandbox.workspaceDir,
        defaultContainerRoot: sandbox.containerWorkdir,
        mounts,
      }),
    ).signals-error(/Path escapes sandbox root/);
  });

  (deftest "prefers custom bind mounts over default workspace mount at /workspace", () => {
    const sandbox = createSandbox({
      docker: {
        ...createSandbox().docker,
        binds: ["/tmp/override:/workspace:ro"],
      },
    });
    const mounts = buildSandboxFsMounts(sandbox);
    const resolved = resolveSandboxFsPathWithMounts({
      filePath: "/workspace/docs/AGENTS.md",
      cwd: sandbox.workspaceDir,
      defaultWorkspaceRoot: sandbox.workspaceDir,
      defaultContainerRoot: sandbox.containerWorkdir,
      mounts,
    });

    (expect* resolved.hostPath).is(path.join(path.resolve("/tmp/override"), "docs", "AGENTS.md"));
    (expect* resolved.writable).is(false);
  });
});
