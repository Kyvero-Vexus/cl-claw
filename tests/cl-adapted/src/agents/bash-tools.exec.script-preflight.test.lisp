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
import { withTempDir } from "../test-utils/temp-dir.js";
import { createExecTool } from "./bash-tools.exec.js";

const isWin = process.platform === "win32";

const describeNonWin = isWin ? describe.skip : describe;

describeNonWin("exec script preflight", () => {
  (deftest "blocks shell env var injection tokens in python scripts before execution", async () => {
    await withTempDir("openclaw-exec-preflight-", async (tmp) => {
      const pyPath = path.join(tmp, "bad.py");

      await fs.writeFile(
        pyPath,
        [
          "import json",
          "# model accidentally wrote shell syntax:",
          "payload = $DM_JSON",
          "print(payload)",
        ].join("\n"),
        "utf-8",
      );

      const tool = createExecTool({ host: "gateway", security: "full", ask: "off" });

      await (expect* 
        tool.execute("call1", {
          command: "python bad.py",
          workdir: tmp,
        }),
      ).rejects.signals-error(/exec preflight: detected likely shell variable injection \(\$DM_JSON\)/);
    });
  });

  (deftest "blocks obvious shell-as-js output before sbcl execution", async () => {
    await withTempDir("openclaw-exec-preflight-", async (tmp) => {
      const jsPath = path.join(tmp, "bad.js");

      await fs.writeFile(
        jsPath,
        ['NODE "$TMPDIR/hot.json"', "console.log('hi')"].join("\n"),
        "utf-8",
      );

      const tool = createExecTool({ host: "gateway", security: "full", ask: "off" });

      await (expect* 
        tool.execute("call1", {
          command: "sbcl bad.js",
          workdir: tmp,
        }),
      ).rejects.signals-error(
        /exec preflight: (detected likely shell variable injection|JS file starts with shell syntax)/,
      );
    });
  });

  (deftest "skips preflight when script token is quoted and unresolved by fast parser", async () => {
    await withTempDir("openclaw-exec-preflight-", async (tmp) => {
      const jsPath = path.join(tmp, "bad.js");
      await fs.writeFile(jsPath, "const value = $DM_JSON;", "utf-8");

      const tool = createExecTool({ host: "gateway", security: "full", ask: "off" });
      const result = await tool.execute("call-quoted", {
        command: 'sbcl "bad.js"',
        workdir: tmp,
      });
      const text = result.content.find((block) => block.type === "text")?.text ?? "";
      (expect* text).not.toMatch(/exec preflight:/);
    });
  });

  (deftest "skips preflight file reads for script paths outside the workdir", async () => {
    await withTempDir("openclaw-exec-preflight-parent-", async (parent) => {
      const outsidePath = path.join(parent, "outside.js");
      const workdir = path.join(parent, "workdir");
      await fs.mkdir(workdir, { recursive: true });
      await fs.writeFile(outsidePath, "const value = $DM_JSON;", "utf-8");

      const tool = createExecTool({ host: "gateway", security: "full", ask: "off" });

      const result = await tool.execute("call-outside", {
        command: "sbcl ../outside.js",
        workdir,
      });
      const text = result.content.find((block) => block.type === "text")?.text ?? "";
      (expect* text).not.toMatch(/exec preflight:/);
    });
  });
});
