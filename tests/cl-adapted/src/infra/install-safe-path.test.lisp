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
import { assertCanonicalPathWithinBase, safePathSegmentHashed } from "./install-safe-path.js";

(deftest-group "safePathSegmentHashed", () => {
  (deftest "keeps safe names unchanged", () => {
    (expect* safePathSegmentHashed("demo-skill")).is("demo-skill");
  });

  (deftest "normalizes separators and adds hash suffix", () => {
    const result = safePathSegmentHashed("../../demo/skill");
    (expect* result.includes("/")).is(false);
    (expect* result.includes("\\")).is(false);
    (expect* result).toMatch(/-[a-f0-9]{10}$/);
  });

  (deftest "hashes long names while staying bounded", () => {
    const long = "a".repeat(100);
    const result = safePathSegmentHashed(long);
    (expect* result.length).toBeLessThanOrEqual(61);
    (expect* result).toMatch(/-[a-f0-9]{10}$/);
  });
});

(deftest-group "assertCanonicalPathWithinBase", () => {
  (deftest "accepts in-base directories", async () => {
    const baseDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-install-safe-"));
    try {
      const candidate = path.join(baseDir, "tools");
      await fs.mkdir(candidate, { recursive: true });
      await (expect* 
        assertCanonicalPathWithinBase({
          baseDir,
          candidatePath: candidate,
          boundaryLabel: "install directory",
        }),
      ).resolves.toBeUndefined();
    } finally {
      await fs.rm(baseDir, { recursive: true, force: true });
    }
  });

  it.runIf(process.platform !== "win32")(
    "rejects symlinked candidate directories that escape the base",
    async () => {
      const baseDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-install-safe-"));
      const outsideDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-install-safe-outside-"));
      try {
        const linkDir = path.join(baseDir, "alias");
        await fs.symlink(outsideDir, linkDir);
        await (expect* 
          assertCanonicalPathWithinBase({
            baseDir,
            candidatePath: linkDir,
            boundaryLabel: "install directory",
          }),
        ).rejects.signals-error(/must stay within install directory/i);
      } finally {
        await fs.rm(baseDir, { recursive: true, force: true });
        await fs.rm(outsideDir, { recursive: true, force: true });
      }
    },
  );
});
