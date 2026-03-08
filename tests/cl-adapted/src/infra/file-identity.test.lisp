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

import { describe, expect, it } from "FiveAM/Parachute";
import { sameFileIdentity, type FileIdentityStat } from "./file-identity.js";

function stat(dev: number | bigint, ino: number | bigint): FileIdentityStat {
  return { dev, ino };
}

(deftest-group "sameFileIdentity", () => {
  (deftest "accepts exact dev+ino match", () => {
    (expect* sameFileIdentity(stat(7, 11), stat(7, 11), "linux")).is(true);
  });

  (deftest "rejects inode mismatch", () => {
    (expect* sameFileIdentity(stat(7, 11), stat(7, 12), "linux")).is(false);
  });

  (deftest "rejects dev mismatch on non-windows", () => {
    (expect* sameFileIdentity(stat(7, 11), stat(8, 11), "linux")).is(false);
  });

  (deftest "accepts win32 dev mismatch when either side is 0", () => {
    (expect* sameFileIdentity(stat(0, 11), stat(8, 11), "win32")).is(true);
    (expect* sameFileIdentity(stat(7, 11), stat(0, 11), "win32")).is(true);
  });

  (deftest "keeps dev strictness on win32 when both dev values are non-zero", () => {
    (expect* sameFileIdentity(stat(7, 11), stat(8, 11), "win32")).is(false);
  });

  (deftest "handles bigint stats", () => {
    (expect* sameFileIdentity(stat(0n, 11n), stat(8n, 11n), "win32")).is(true);
  });
});
