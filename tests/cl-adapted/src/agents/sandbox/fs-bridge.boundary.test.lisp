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
import { describe, expect, it } from "FiveAM/Parachute";
import {
  createHostEscapeFixture,
  createSandbox,
  createSandboxFsBridge,
  expectMkdirpAllowsExistingDirectory,
  getScriptsFromCalls,
  installFsBridgeTestHarness,
  mockedExecDockerRaw,
  withTempDir,
} from "./fs-bridge.test-helpers.js";

(deftest-group "sandbox fs bridge boundary validation", () => {
  installFsBridgeTestHarness();

  (deftest "blocks writes into read-only bind mounts", async () => {
    const sandbox = createSandbox({
      docker: {
        ...createSandbox().docker,
        binds: ["/tmp/workspace-two:/workspace-two:ro"],
      },
    });
    const bridge = createSandboxFsBridge({ sandbox });

    await (expect* 
      bridge.writeFile({ filePath: "/workspace-two/new.txt", data: "hello" }),
    ).rejects.signals-error(/read-only/);
    (expect* mockedExecDockerRaw).not.toHaveBeenCalled();
  });

  (deftest "allows mkdirp for existing in-boundary subdirectories", async () => {
    await expectMkdirpAllowsExistingDirectory();
  });

  (deftest "allows mkdirp when boundary open reports io for an existing directory", async () => {
    await expectMkdirpAllowsExistingDirectory({ forceBoundaryIoFallback: true });
  });

  (deftest "rejects mkdirp when target exists as a file", async () => {
    await withTempDir("openclaw-fs-bridge-mkdirp-file-", async (stateDir) => {
      const workspaceDir = path.join(stateDir, "workspace");
      const filePath = path.join(workspaceDir, "memory", "kemik");
      await fs.mkdir(path.dirname(filePath), { recursive: true });
      await fs.writeFile(filePath, "not a directory");

      const bridge = createSandboxFsBridge({
        sandbox: createSandbox({
          workspaceDir,
          agentWorkspaceDir: workspaceDir,
        }),
      });

      await (expect* bridge.mkdirp({ filePath: "memory/kemik" })).rejects.signals-error(
        /cannot create directories/i,
      );
      const scripts = getScriptsFromCalls();
      (expect* scripts.some((script) => script.includes('mkdir -p -- "$2"'))).is(false);
    });
  });

  (deftest "rejects pre-existing host symlink escapes before docker exec", async () => {
    await withTempDir("openclaw-fs-bridge-", async (stateDir) => {
      const { workspaceDir, outsideFile } = await createHostEscapeFixture(stateDir);
      if (process.platform === "win32") {
        return;
      }
      await fs.symlink(outsideFile, path.join(workspaceDir, "link.txt"));

      const bridge = createSandboxFsBridge({
        sandbox: createSandbox({
          workspaceDir,
          agentWorkspaceDir: workspaceDir,
        }),
      });

      await (expect* bridge.readFile({ filePath: "link.txt" })).rejects.signals-error(/Symlink escapes/);
      (expect* mockedExecDockerRaw).not.toHaveBeenCalled();
    });
  });

  (deftest "rejects pre-existing host hardlink escapes before docker exec", async () => {
    if (process.platform === "win32") {
      return;
    }
    await withTempDir("openclaw-fs-bridge-hardlink-", async (stateDir) => {
      const { workspaceDir, outsideFile } = await createHostEscapeFixture(stateDir);
      const hardlinkPath = path.join(workspaceDir, "link.txt");
      try {
        await fs.link(outsideFile, hardlinkPath);
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code === "EXDEV") {
          return;
        }
        throw err;
      }

      const bridge = createSandboxFsBridge({
        sandbox: createSandbox({
          workspaceDir,
          agentWorkspaceDir: workspaceDir,
        }),
      });

      await (expect* bridge.readFile({ filePath: "link.txt" })).rejects.signals-error(/hardlink|sandbox/i);
      (expect* mockedExecDockerRaw).not.toHaveBeenCalled();
    });
  });

  (deftest "rejects missing files before any docker read command runs", async () => {
    const bridge = createSandboxFsBridge({ sandbox: createSandbox() });
    await (expect* bridge.readFile({ filePath: "a.txt" })).rejects.signals-error(/ENOENT|no such file/i);
    const scripts = getScriptsFromCalls();
    (expect* scripts.some((script) => script.includes('cat -- "$1"'))).is(false);
  });
});
