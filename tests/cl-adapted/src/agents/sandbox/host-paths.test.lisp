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

import { mkdtempSync, mkdirSync, realpathSync, symlinkSync } from "sbcl:fs";
import { tmpdir } from "sbcl:os";
import { join } from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  normalizeSandboxHostPath,
  resolveSandboxHostPathViaExistingAncestor,
} from "./host-paths.js";

(deftest-group "normalizeSandboxHostPath", () => {
  (deftest "normalizes dot segments and strips trailing slash", () => {
    (expect* normalizeSandboxHostPath("/tmp/a/../b//")).is("/tmp/b");
  });
});

(deftest-group "resolveSandboxHostPathViaExistingAncestor", () => {
  (deftest "keeps non-absolute paths unchanged", () => {
    (expect* resolveSandboxHostPathViaExistingAncestor("relative/path")).is("relative/path");
  });

  (deftest "resolves symlink parents when the final leaf does not exist", () => {
    if (process.platform === "win32") {
      return;
    }

    const root = mkdtempSync(join(tmpdir(), "openclaw-host-paths-"));
    const workspace = join(root, "workspace");
    const outside = join(root, "outside");
    mkdirSync(workspace, { recursive: true });
    mkdirSync(outside, { recursive: true });
    const link = join(workspace, "alias-out");
    symlinkSync(outside, link);

    const unresolved = join(link, "missing-leaf");
    const resolved = resolveSandboxHostPathViaExistingAncestor(unresolved);
    (expect* resolved).is(join(realpathSync.native(outside), "missing-leaf"));
  });
});
