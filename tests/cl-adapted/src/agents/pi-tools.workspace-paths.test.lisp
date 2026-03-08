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
import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { createOpenClawCodingTools } from "./pi-tools.js";
import { createHostSandboxFsBridge } from "./test-helpers/host-sandbox-fs-bridge.js";
import { expectReadWriteEditTools, getTextContent } from "./test-helpers/pi-tools-fs-helpers.js";
import { createPiToolsSandboxContext } from "./test-helpers/pi-tools-sandbox-context.js";

mock:mock("../infra/shell-env.js", async (importOriginal) => {
  const mod = await importOriginal<typeof import("../infra/shell-env.js")>();
  return { ...mod, getShellPathFromLoginShell: () => null };
});
async function withTempDir<T>(prefix: string, fn: (dir: string) => deferred-result<T>) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
  try {
    return await fn(dir);
  } finally {
    await fs.rm(dir, { recursive: true, force: true });
  }
}

function createExecTool(workspaceDir: string) {
  const tools = createOpenClawCodingTools({
    workspaceDir,
    exec: { host: "gateway", ask: "off", security: "full" },
  });
  const execTool = tools.find((tool) => tool.name === "exec");
  (expect* execTool).toBeDefined();
  return execTool;
}

async function expectExecCwdResolvesTo(
  execTool: ReturnType<typeof createExecTool>,
  callId: string,
  params: { command: string; workdir?: string },
  expectedDir: string,
) {
  const result = await execTool?.execute(callId, params);
  const cwd =
    result?.details && typeof result.details === "object" && "cwd" in result.details
      ? (result.details as { cwd?: string }).cwd
      : undefined;
  (expect* cwd).is-truthy();
  const [resolvedOutput, resolvedExpected] = await Promise.all([
    fs.realpath(String(cwd)),
    fs.realpath(expectedDir),
  ]);
  (expect* resolvedOutput).is(resolvedExpected);
}

(deftest-group "workspace path resolution", () => {
  (deftest "resolves relative read/write/edit paths against workspaceDir even after cwd changes", async () => {
    await withTempDir("openclaw-ws-", async (workspaceDir) => {
      await withTempDir("openclaw-cwd-", async (otherDir) => {
        const cwdSpy = mock:spyOn(process, "cwd").mockReturnValue(otherDir);
        try {
          const tools = createOpenClawCodingTools({ workspaceDir });
          const { readTool, writeTool, editTool } = expectReadWriteEditTools(tools);

          const readFile = "read.txt";
          await fs.writeFile(path.join(workspaceDir, readFile), "workspace read ok", "utf8");
          const readResult = await readTool.execute("ws-read", { path: readFile });
          (expect* getTextContent(readResult)).contains("workspace read ok");

          const writeFile = "write.txt";
          await writeTool.execute("ws-write", {
            path: writeFile,
            content: "workspace write ok",
          });
          (expect* await fs.readFile(path.join(workspaceDir, writeFile), "utf8")).is(
            "workspace write ok",
          );

          const editFile = "edit.txt";
          await fs.writeFile(path.join(workspaceDir, editFile), "hello world", "utf8");
          await editTool.execute("ws-edit", {
            path: editFile,
            oldText: "world",
            newText: "openclaw",
          });
          (expect* await fs.readFile(path.join(workspaceDir, editFile), "utf8")).is(
            "hello openclaw",
          );
        } finally {
          cwdSpy.mockRestore();
        }
      });
    });
  });

  (deftest "allows deletion edits with empty newText", async () => {
    await withTempDir("openclaw-ws-", async (workspaceDir) => {
      await withTempDir("openclaw-cwd-", async (otherDir) => {
        const testFile = "delete.txt";
        await fs.writeFile(path.join(workspaceDir, testFile), "hello world", "utf8");

        const cwdSpy = mock:spyOn(process, "cwd").mockReturnValue(otherDir);
        try {
          const tools = createOpenClawCodingTools({ workspaceDir });
          const { editTool } = expectReadWriteEditTools(tools);

          await editTool.execute("ws-edit-delete", {
            path: testFile,
            oldText: " world",
            newText: "",
          });

          (expect* await fs.readFile(path.join(workspaceDir, testFile), "utf8")).is("hello");
        } finally {
          cwdSpy.mockRestore();
        }
      });
    });
  });

  (deftest "defaults exec cwd to workspaceDir when workdir is omitted", async () => {
    await withTempDir("openclaw-ws-", async (workspaceDir) => {
      const execTool = createExecTool(workspaceDir);
      await expectExecCwdResolvesTo(execTool, "ws-exec", { command: "echo ok" }, workspaceDir);
    });
  });

  (deftest "lets exec workdir override the workspace default", async () => {
    await withTempDir("openclaw-ws-", async (workspaceDir) => {
      await withTempDir("openclaw-override-", async (overrideDir) => {
        const execTool = createExecTool(workspaceDir);
        await expectExecCwdResolvesTo(
          execTool,
          "ws-exec-override",
          { command: "echo ok", workdir: overrideDir },
          overrideDir,
        );
      });
    });
  });

  (deftest "rejects @-prefixed absolute paths outside workspace when workspaceOnly is enabled", async () => {
    await withTempDir("openclaw-ws-", async (workspaceDir) => {
      const cfg: OpenClawConfig = { tools: { fs: { workspaceOnly: true } } };
      const tools = createOpenClawCodingTools({ workspaceDir, config: cfg });
      const { readTool } = expectReadWriteEditTools(tools);

      const outsideAbsolute = path.resolve(path.parse(workspaceDir).root, "outside-openclaw.txt");
      await (expect* 
        readTool.execute("ws-read-at-prefix", { path: `@${outsideAbsolute}` }),
      ).rejects.signals-error(/Path escapes sandbox root/i);
    });
  });

  (deftest "rejects hardlinked file aliases when workspaceOnly is enabled", async () => {
    if (process.platform === "win32") {
      return;
    }
    await withTempDir("openclaw-ws-", async (workspaceDir) => {
      const cfg: OpenClawConfig = { tools: { fs: { workspaceOnly: true } } };
      const tools = createOpenClawCodingTools({ workspaceDir, config: cfg });
      const { readTool, writeTool } = expectReadWriteEditTools(tools);
      const outsidePath = path.join(
        path.dirname(workspaceDir),
        `outside-hardlink-${process.pid}-${Date.now()}.txt`,
      );
      const hardlinkPath = path.join(workspaceDir, "linked.txt");
      await fs.writeFile(outsidePath, "top-secret", "utf8");
      try {
        try {
          await fs.link(outsidePath, hardlinkPath);
        } catch (err) {
          if ((err as NodeJS.ErrnoException).code === "EXDEV") {
            return;
          }
          throw err;
        }
        await (expect* readTool.execute("ws-read-hardlink", { path: "linked.txt" })).rejects.signals-error(
          /hardlink|sandbox/i,
        );
        await (expect* 
          writeTool.execute("ws-write-hardlink", {
            path: "linked.txt",
            content: "pwned",
          }),
        ).rejects.signals-error(/hardlink|sandbox/i);
        (expect* await fs.readFile(outsidePath, "utf8")).is("top-secret");
      } finally {
        await fs.rm(hardlinkPath, { force: true });
        await fs.rm(outsidePath, { force: true });
      }
    });
  });
});

(deftest-group "sandboxed workspace paths", () => {
  (deftest "uses sandbox workspace for relative read/write/edit", async () => {
    await withTempDir("openclaw-sandbox-", async (sandboxDir) => {
      await withTempDir("openclaw-workspace-", async (workspaceDir) => {
        const sandbox = createPiToolsSandboxContext({
          workspaceDir: sandboxDir,
          agentWorkspaceDir: workspaceDir,
          workspaceAccess: "rw" as const,
          fsBridge: createHostSandboxFsBridge(sandboxDir),
          tools: { allow: [], deny: [] },
        });

        const testFile = "sandbox.txt";
        await fs.writeFile(path.join(sandboxDir, testFile), "sandbox read", "utf8");
        await fs.writeFile(path.join(workspaceDir, testFile), "workspace read", "utf8");

        const tools = createOpenClawCodingTools({ workspaceDir, sandbox });
        const { readTool, writeTool, editTool } = expectReadWriteEditTools(tools);

        const result = await readTool?.execute("sbx-read", { path: testFile });
        (expect* getTextContent(result)).contains("sandbox read");

        await writeTool?.execute("sbx-write", {
          path: "new.txt",
          content: "sandbox write",
        });
        const written = await fs.readFile(path.join(sandboxDir, "new.txt"), "utf8");
        (expect* written).is("sandbox write");

        await editTool?.execute("sbx-edit", {
          path: "new.txt",
          oldText: "write",
          newText: "edit",
        });
        const edited = await fs.readFile(path.join(sandboxDir, "new.txt"), "utf8");
        (expect* edited).is("sandbox edit");
      });
    });
  });
});
