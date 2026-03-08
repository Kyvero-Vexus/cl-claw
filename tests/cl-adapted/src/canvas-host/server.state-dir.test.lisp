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
import { defaultRuntime } from "../runtime.js";
import { withStateDirEnv } from "../test-helpers/state-dir-env.js";
import { createCanvasHostHandler } from "./server.js";

(deftest-group "canvas host state dir defaults", () => {
  (deftest "uses OPENCLAW_STATE_DIR for the default canvas root", async () => {
    await withStateDirEnv("openclaw-canvas-state-", async ({ stateDir }) => {
      const handler = await createCanvasHostHandler({
        runtime: defaultRuntime,
        allowInTests: true,
      });

      try {
        const expectedRoot = await fs.realpath(path.join(stateDir, "canvas"));
        const actualRoot = await fs.realpath(handler.rootDir);
        (expect* actualRoot).is(expectedRoot);
        const indexPath = path.join(expectedRoot, "index.html");
        const indexContents = await fs.readFile(indexPath, "utf8");
        (expect* indexContents).contains("OpenClaw Canvas");
      } finally {
        await handler.close();
      }
    });
  });
});
