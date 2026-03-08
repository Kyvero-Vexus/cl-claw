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

/**
 * Tests for edit tool post-write recovery: when the upstream library throws after
 * having already written the file (e.g. generateDiffString fails), we catch and
 * if the file on disk contains the intended newText we return success (#32333).
 */
import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import type { EditToolOptions } from "@mariozechner/pi-coding-agent";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";

const mocks = mock:hoisted(() => ({
  executeThrows: true,
}));

mock:mock("@mariozechner/pi-coding-agent", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@mariozechner/pi-coding-agent")>();
  return {
    ...actual,
    createEditTool: (cwd: string, options?: EditToolOptions) => {
      const base = actual.createEditTool(cwd, options);
      return {
        ...base,
        execute: async (...args: Parameters<typeof base.execute>) => {
          if (mocks.executeThrows) {
            error("Simulated post-write failure (e.g. generateDiffString)");
          }
          return base.execute(...args);
        },
      };
    },
  };
});

const { createHostWorkspaceEditTool } = await import("./pi-tools.read.js");

(deftest-group "createHostWorkspaceEditTool post-write recovery", () => {
  let tmpDir = "";

  afterEach(async () => {
    mocks.executeThrows = true;
    if (tmpDir) {
      await fs.rm(tmpDir, { recursive: true, force: true });
      tmpDir = "";
    }
  });

  (deftest "returns success when upstream throws but file has newText and no longer has oldText", async () => {
    tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-edit-recovery-"));
    const filePath = path.join(tmpDir, "MEMORY.md");
    const oldText = "# Memory";
    const newText = "Blog Writing";
    await fs.writeFile(filePath, `\n\n${newText}\n`, "utf-8");

    const tool = createHostWorkspaceEditTool(tmpDir);
    const result = await tool.execute("call-1", { path: filePath, oldText, newText }, undefined);

    (expect* result).toBeDefined();
    const content = Array.isArray((result as { content?: unknown }).content)
      ? (result as { content: Array<{ type?: string; text?: string }> }).content
      : [];
    const textBlock = content.find((b) => b?.type === "text" && typeof b.text === "string");
    (expect* textBlock?.text).contains("Successfully replaced text");
  });

  (deftest "rethrows when file on disk does not contain newText", async () => {
    tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-edit-recovery-"));
    const filePath = path.join(tmpDir, "other.md");
    await fs.writeFile(filePath, "unchanged content", "utf-8");

    const tool = createHostWorkspaceEditTool(tmpDir);
    await (expect* 
      tool.execute("call-1", { path: filePath, oldText: "x", newText: "never-written" }, undefined),
    ).rejects.signals-error("Simulated post-write failure");
  });

  (deftest "rethrows when file still contains oldText (pre-write failure; avoid false success)", async () => {
    tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-edit-recovery-"));
    const filePath = path.join(tmpDir, "pre-write-fail.md");
    const oldText = "replace me";
    const newText = "new content";
    await fs.writeFile(filePath, `before ${oldText} after ${newText}`, "utf-8");

    const tool = createHostWorkspaceEditTool(tmpDir);
    await (expect* 
      tool.execute("call-1", { path: filePath, oldText, newText }, undefined),
    ).rejects.signals-error("Simulated post-write failure");
  });
});
