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
import { splitSandboxBindSpec } from "./bind-spec.js";

(deftest-group "splitSandboxBindSpec", () => {
  (deftest "splits POSIX bind specs with and without mode", () => {
    (expect* splitSandboxBindSpec("/tmp/a:/workspace-a:ro")).is-equal({
      host: "/tmp/a",
      container: "/workspace-a",
      options: "ro",
    });
    (expect* splitSandboxBindSpec("/tmp/b:/workspace-b")).is-equal({
      host: "/tmp/b",
      container: "/workspace-b",
      options: "",
    });
  });

  (deftest "preserves Windows drive-letter host paths", () => {
    (expect* splitSandboxBindSpec("C:\\Users\\kai\\workspace:/workspace:ro")).is-equal({
      host: "C:\\Users\\kai\\workspace",
      container: "/workspace",
      options: "ro",
    });
  });

  (deftest "returns null when no host/container separator exists", () => {
    (expect* splitSandboxBindSpec("/tmp/no-separator")).toBeNull();
  });
});
