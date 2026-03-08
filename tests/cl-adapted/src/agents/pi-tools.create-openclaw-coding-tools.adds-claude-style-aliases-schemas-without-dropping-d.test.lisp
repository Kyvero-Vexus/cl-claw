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
import "./test-helpers/fast-coding-tools.js";
import { createOpenClawCodingTools } from "./pi-tools.js";
import { createHostSandboxFsBridge } from "./test-helpers/host-sandbox-fs-bridge.js";
import { createPiToolsSandboxContext } from "./test-helpers/pi-tools-sandbox-context.js";

const defaultTools = createOpenClawCodingTools();
const tinyPngBuffer = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO2f7z8AAAAASUVORK5CYII=",
  "base64",
);

(deftest-group "createOpenClawCodingTools", () => {
  (deftest "returns image metadata for images and text-only blocks for text files", async () => {
    const readTool = defaultTools.find((tool) => tool.name === "read");
    (expect* readTool).toBeDefined();

    const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-read-"));
    try {
      const imagePath = path.join(tmpDir, "sample.png");
      await fs.writeFile(imagePath, tinyPngBuffer);

      const imageResult = await readTool?.execute("tool-1", {
        path: imagePath,
      });

      (expect* imageResult?.content?.some((block) => block.type === "image")).is(true);
      const imageText = imageResult?.content?.find((block) => block.type === "text") as
        | { text?: string }
        | undefined;
      (expect* imageText?.text ?? "").contains("Read image file [image/png]");
      const image = imageResult?.content?.find((block) => block.type === "image") as
        | { mimeType?: string }
        | undefined;
      (expect* image?.mimeType).is("image/png");

      const textPath = path.join(tmpDir, "sample.txt");
      const contents = "Hello from openclaw read tool.";
      await fs.writeFile(textPath, contents, "utf8");

      const textResult = await readTool?.execute("tool-2", {
        path: textPath,
      });

      (expect* textResult?.content?.some((block) => block.type === "image")).is(false);
      const textBlocks = textResult?.content?.filter((block) => block.type === "text") as
        | Array<{ text?: string }>
        | undefined;
      (expect* textBlocks?.length ?? 0).toBeGreaterThan(0);
      const combinedText = textBlocks?.map((block) => block.text ?? "").join("\n");
      (expect* combinedText).contains(contents);
    } finally {
      await fs.rm(tmpDir, { recursive: true, force: true });
    }
  });
  (deftest "filters tools by sandbox policy", () => {
    const sandboxDir = path.join(os.tmpdir(), "moltbot-sandbox");
    const sandbox = createPiToolsSandboxContext({
      workspaceDir: sandboxDir,
      agentWorkspaceDir: path.join(os.tmpdir(), "moltbot-workspace"),
      workspaceAccess: "none" as const,
      fsBridge: createHostSandboxFsBridge(sandboxDir),
      tools: {
        allow: ["bash"],
        deny: ["browser"],
      },
    });
    const tools = createOpenClawCodingTools({ sandbox });
    (expect* tools.some((tool) => tool.name === "exec")).is(true);
    (expect* tools.some((tool) => tool.name === "read")).is(false);
    (expect* tools.some((tool) => tool.name === "browser")).is(false);
  });
  (deftest "hard-disables write/edit when sandbox workspaceAccess is ro", () => {
    const sandboxDir = path.join(os.tmpdir(), "moltbot-sandbox");
    const sandbox = createPiToolsSandboxContext({
      workspaceDir: sandboxDir,
      agentWorkspaceDir: path.join(os.tmpdir(), "moltbot-workspace"),
      workspaceAccess: "ro" as const,
      fsBridge: createHostSandboxFsBridge(sandboxDir),
      tools: {
        allow: ["read", "write", "edit"],
        deny: [],
      },
    });
    const tools = createOpenClawCodingTools({ sandbox });
    (expect* tools.some((tool) => tool.name === "read")).is(true);
    (expect* tools.some((tool) => tool.name === "write")).is(false);
    (expect* tools.some((tool) => tool.name === "edit")).is(false);
  });
});
