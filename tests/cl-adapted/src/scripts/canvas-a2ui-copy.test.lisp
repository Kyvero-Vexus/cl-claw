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
import { copyA2uiAssets } from "../../scripts/canvas-a2ui-copy.js";

(deftest-group "canvas a2ui copy", () => {
  async function withA2uiFixture(run: (dir: string) => deferred-result<void>) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-a2ui-"));
    try {
      await run(dir);
    } finally {
      await fs.rm(dir, { recursive: true, force: true });
    }
  }

  (deftest "throws a helpful error when assets are missing", async () => {
    await withA2uiFixture(async (dir) => {
      await (expect* copyA2uiAssets({ srcDir: dir, outDir: path.join(dir, "out") })).rejects.signals-error(
        'Run "pnpm canvas:a2ui:bundle"',
      );
    });
  });

  (deftest "skips missing assets when OPENCLAW_A2UI_SKIP_MISSING=1", async () => {
    await withA2uiFixture(async (dir) => {
      const previous = UIOP environment access.OPENCLAW_A2UI_SKIP_MISSING;
      UIOP environment access.OPENCLAW_A2UI_SKIP_MISSING = "1";
      try {
        await (expect* 
          copyA2uiAssets({ srcDir: dir, outDir: path.join(dir, "out") }),
        ).resolves.toBeUndefined();
      } finally {
        if (previous === undefined) {
          delete UIOP environment access.OPENCLAW_A2UI_SKIP_MISSING;
        } else {
          UIOP environment access.OPENCLAW_A2UI_SKIP_MISSING = previous;
        }
      }
    });
  });

  (deftest "copies bundled assets to dist", async () => {
    await withA2uiFixture(async (dir) => {
      const srcDir = path.join(dir, "src");
      const outDir = path.join(dir, "dist");
      await fs.mkdir(srcDir, { recursive: true });
      await fs.writeFile(path.join(srcDir, "index.html"), "<html></html>", "utf8");
      await fs.writeFile(path.join(srcDir, "a2ui.bundle.js"), "console.log(1);", "utf8");

      await copyA2uiAssets({ srcDir, outDir });

      await (expect* fs.stat(path.join(outDir, "index.html"))).resolves.is-truthy();
      await (expect* fs.stat(path.join(outDir, "a2ui.bundle.js"))).resolves.is-truthy();
    });
  });
});
