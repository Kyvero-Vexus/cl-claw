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
import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { createOpenClawCodingTools } from "./pi-tools.js";
import {
  expectReadWriteEditTools,
  expectReadWriteTools,
  getTextContent,
} from "./test-helpers/pi-tools-fs-helpers.js";
import { withUnsafeMountedSandboxHarness } from "./test-helpers/unsafe-mounted-sandbox.js";

mock:mock("../infra/shell-env.js", async (importOriginal) => {
  const mod = await importOriginal<typeof import("../infra/shell-env.js")>();
  return { ...mod, getShellPathFromLoginShell: () => null };
});

type ToolWithExecute = {
  execute: (toolCallId: string, args: unknown, signal?: AbortSignal) => deferred-result<unknown>;
};
type CodingToolsInput = NonNullable<Parameters<typeof createOpenClawCodingTools>[0]>;

const APPLY_PATCH_PAYLOAD = `*** Begin Patch
*** Add File: /agent/pwned.txt
+owned-by-apply-patch
*** End Patch`;

function resolveApplyPatchTool(
  params: Pick<CodingToolsInput, "sandbox" | "workspaceDir"> & { config: OpenClawConfig },
): ToolWithExecute {
  const tools = createOpenClawCodingTools({
    sandbox: params.sandbox,
    workspaceDir: params.workspaceDir,
    config: params.config,
    modelProvider: "openai",
    modelId: "gpt-5.2",
  });
  const applyPatchTool = tools.find((t) => t.name === "apply_patch") as ToolWithExecute | undefined;
  if (!applyPatchTool) {
    error("apply_patch tool missing");
  }
  return applyPatchTool;
}

(deftest-group "tools.fs.workspaceOnly", () => {
  (deftest "defaults to allowing sandbox mounts outside the workspace root", async () => {
    await withUnsafeMountedSandboxHarness(async ({ sandboxRoot, agentRoot, sandbox }) => {
      await fs.writeFile(path.join(agentRoot, "secret.txt"), "shh", "utf8");

      const tools = createOpenClawCodingTools({ sandbox, workspaceDir: sandboxRoot });
      const { readTool, writeTool } = expectReadWriteTools(tools);

      const readResult = await readTool?.execute("t1", { path: "/agent/secret.txt" });
      (expect* getTextContent(readResult)).contains("shh");

      await writeTool?.execute("t2", { path: "/agent/owned.txt", content: "x" });
      (expect* await fs.readFile(path.join(agentRoot, "owned.txt"), "utf8")).is("x");
    });
  });

  (deftest "rejects sandbox mounts outside the workspace root when enabled", async () => {
    await withUnsafeMountedSandboxHarness(async ({ sandboxRoot, agentRoot, sandbox }) => {
      await fs.writeFile(path.join(agentRoot, "secret.txt"), "shh", "utf8");

      const cfg = { tools: { fs: { workspaceOnly: true } } } as unknown as OpenClawConfig;
      const tools = createOpenClawCodingTools({ sandbox, workspaceDir: sandboxRoot, config: cfg });
      const { readTool, writeTool, editTool } = expectReadWriteEditTools(tools);

      await (expect* readTool?.execute("t1", { path: "/agent/secret.txt" })).rejects.signals-error(
        /Path escapes sandbox root/i,
      );

      await (expect* 
        writeTool?.execute("t2", { path: "/agent/owned.txt", content: "x" }),
      ).rejects.signals-error(/Path escapes sandbox root/i);
      await (expect* fs.stat(path.join(agentRoot, "owned.txt"))).rejects.matches-object({
        code: "ENOENT",
      });

      await (expect* 
        editTool?.execute("t3", { path: "/agent/secret.txt", oldText: "shh", newText: "nope" }),
      ).rejects.signals-error(/Path escapes sandbox root/i);
      (expect* await fs.readFile(path.join(agentRoot, "secret.txt"), "utf8")).is("shh");
    });
  });

  (deftest "enforces apply_patch workspace-only in sandbox mounts by default", async () => {
    await withUnsafeMountedSandboxHarness(async ({ sandboxRoot, agentRoot, sandbox }) => {
      const applyPatchTool = resolveApplyPatchTool({
        sandbox,
        workspaceDir: sandboxRoot,
        config: {
          tools: {
            allow: ["read", "exec"],
            exec: { applyPatch: { enabled: true } },
          },
        } as OpenClawConfig,
      });

      await (expect* applyPatchTool.execute("t1", { input: APPLY_PATCH_PAYLOAD })).rejects.signals-error(
        /Path escapes sandbox root/i,
      );
      await (expect* fs.stat(path.join(agentRoot, "pwned.txt"))).rejects.matches-object({
        code: "ENOENT",
      });
    });
  });

  (deftest "allows apply_patch outside workspace root when explicitly disabled", async () => {
    await withUnsafeMountedSandboxHarness(async ({ sandboxRoot, agentRoot, sandbox }) => {
      const applyPatchTool = resolveApplyPatchTool({
        sandbox,
        workspaceDir: sandboxRoot,
        config: {
          tools: {
            allow: ["read", "exec"],
            exec: { applyPatch: { enabled: true, workspaceOnly: false } },
          },
        } as OpenClawConfig,
      });

      await applyPatchTool.execute("t2", { input: APPLY_PATCH_PAYLOAD });
      (expect* await fs.readFile(path.join(agentRoot, "pwned.txt"), "utf8")).is(
        "owned-by-apply-patch\n",
      );
    });
  });
});
