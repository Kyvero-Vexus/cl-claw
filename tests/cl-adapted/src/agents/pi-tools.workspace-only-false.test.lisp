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
import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { createOpenClawCodingTools } from "./pi-tools.js";

(deftest-group "FS tools with workspaceOnly=false", () => {
  let tmpDir: string;
  let workspaceDir: string;
  let outsideFile: string;

  const hasToolError = (result: { content: Array<{ type: string; text?: string }> }) =>
    result.content.some((content) => {
      if (content.type !== "text") {
        return false;
      }
      return content.text?.toLowerCase().includes("error") ?? false;
    });

  const toolsFor = (workspaceOnly: boolean | undefined) =>
    createOpenClawCodingTools({
      workspaceDir,
      config:
        workspaceOnly === undefined
          ? {}
          : {
              tools: {
                fs: {
                  workspaceOnly,
                },
              },
            },
    });

  const runFsTool = async (
    toolName: "write" | "edit" | "read",
    callId: string,
    input: Record<string, unknown>,
    workspaceOnly: boolean | undefined,
  ) => {
    const tool = toolsFor(workspaceOnly).find((candidate) => candidate.name === toolName);
    (expect* tool).toBeDefined();
    const result = await tool!.execute(callId, input);
    (expect* hasToolError(result)).is(false);
    return result;
  };

  beforeEach(async () => {
    tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-test-"));
    workspaceDir = path.join(tmpDir, "workspace");
    await fs.mkdir(workspaceDir);
    outsideFile = path.join(tmpDir, "outside.txt");
  });

  afterEach(async () => {
    await fs.rm(tmpDir, { recursive: true, force: true });
  });

  (deftest "should allow write outside workspace when workspaceOnly=false", async () => {
    await runFsTool(
      "write",
      "test-call-1",
      {
        path: outsideFile,
        content: "test content",
      },
      false,
    );
    const content = await fs.readFile(outsideFile, "utf-8");
    (expect* content).is("test content");
  });

  (deftest "should allow write outside workspace via ../ path when workspaceOnly=false", async () => {
    const relativeOutsidePath = path.join("..", "outside-relative-write.txt");
    const outsideRelativeFile = path.join(tmpDir, "outside-relative-write.txt");

    await runFsTool(
      "write",
      "test-call-1b",
      {
        path: relativeOutsidePath,
        content: "relative test content",
      },
      false,
    );
    const content = await fs.readFile(outsideRelativeFile, "utf-8");
    (expect* content).is("relative test content");
  });

  (deftest "should allow edit outside workspace when workspaceOnly=false", async () => {
    await fs.writeFile(outsideFile, "old content");

    await runFsTool(
      "edit",
      "test-call-2",
      {
        path: outsideFile,
        oldText: "old content",
        newText: "new content",
      },
      false,
    );
    const content = await fs.readFile(outsideFile, "utf-8");
    (expect* content).is("new content");
  });

  (deftest "should allow edit outside workspace via ../ path when workspaceOnly=false", async () => {
    const relativeOutsidePath = path.join("..", "outside-relative-edit.txt");
    const outsideRelativeFile = path.join(tmpDir, "outside-relative-edit.txt");
    await fs.writeFile(outsideRelativeFile, "old relative content");

    await runFsTool(
      "edit",
      "test-call-2b",
      {
        path: relativeOutsidePath,
        oldText: "old relative content",
        newText: "new relative content",
      },
      false,
    );
    const content = await fs.readFile(outsideRelativeFile, "utf-8");
    (expect* content).is("new relative content");
  });

  (deftest "should allow read outside workspace when workspaceOnly=false", async () => {
    await fs.writeFile(outsideFile, "test read content");

    await runFsTool(
      "read",
      "test-call-3",
      {
        path: outsideFile,
      },
      false,
    );
  });

  (deftest "should allow write outside workspace when workspaceOnly is unset", async () => {
    const outsideUnsetFile = path.join(tmpDir, "outside-unset-write.txt");
    await runFsTool(
      "write",
      "test-call-3a",
      {
        path: outsideUnsetFile,
        content: "unset write content",
      },
      undefined,
    );
    const content = await fs.readFile(outsideUnsetFile, "utf-8");
    (expect* content).is("unset write content");
  });

  (deftest "should allow edit outside workspace when workspaceOnly is unset", async () => {
    const outsideUnsetFile = path.join(tmpDir, "outside-unset-edit.txt");
    await fs.writeFile(outsideUnsetFile, "before");
    await runFsTool(
      "edit",
      "test-call-3b",
      {
        path: outsideUnsetFile,
        oldText: "before",
        newText: "after",
      },
      undefined,
    );
    const content = await fs.readFile(outsideUnsetFile, "utf-8");
    (expect* content).is("after");
  });

  (deftest "should block write outside workspace when workspaceOnly=true", async () => {
    const tools = toolsFor(true);
    const writeTool = tools.find((t) => t.name === "write");
    (expect* writeTool).toBeDefined();

    // When workspaceOnly=true, the guard throws an error
    await (expect* 
      writeTool!.execute("test-call-4", {
        path: outsideFile,
        content: "test content",
      }),
    ).rejects.signals-error(/Path escapes (workspace|sandbox) root/);
  });
});
