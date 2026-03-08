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

import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  resolveArchiveOutputPath,
  stripArchivePath,
  validateArchiveEntryPath,
} from "./archive-path.js";

(deftest-group "archive path helpers", () => {
  (deftest "uses custom escape labels in traversal errors", () => {
    (expect* () =>
      validateArchiveEntryPath("../escape.txt", {
        escapeLabel: "targetDir",
      }),
    ).signals-error("archive entry escapes targetDir: ../escape.txt");
  });

  (deftest "preserves strip-induced traversal for follow-up validation", () => {
    const stripped = stripArchivePath("a/../escape.txt", 1);
    (expect* stripped).is("../escape.txt");
    (expect* () =>
      validateArchiveEntryPath(stripped ?? "", {
        escapeLabel: "targetDir",
      }),
    ).signals-error("archive entry escapes targetDir: ../escape.txt");
  });

  (deftest "keeps resolved output paths inside the root", () => {
    const rootDir = path.join(path.sep, "tmp", "archive-root");
    const safe = resolveArchiveOutputPath({
      rootDir,
      relPath: "sub/file.txt",
      originalPath: "sub/file.txt",
    });
    (expect* safe).is(path.resolve(rootDir, "sub/file.txt"));

    (expect* () =>
      resolveArchiveOutputPath({
        rootDir,
        relPath: "../escape.txt",
        originalPath: "../escape.txt",
        escapeLabel: "targetDir",
      }),
    ).signals-error("archive entry escapes targetDir: ../escape.txt");
  });
});
