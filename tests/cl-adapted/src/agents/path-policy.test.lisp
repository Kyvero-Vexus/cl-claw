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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const resolveSandboxInputPathMock = mock:hoisted(() => mock:fn());

mock:mock("./sandbox-paths.js", () => ({
  resolveSandboxInputPath: resolveSandboxInputPathMock,
}));

import { toRelativeWorkspacePath } from "./path-policy.js";

(deftest-group "toRelativeWorkspacePath (windows semantics)", () => {
  beforeEach(() => {
    resolveSandboxInputPathMock.mockReset();
    resolveSandboxInputPathMock.mockImplementation((filePath: string) => filePath);
  });

  (deftest "accepts windows paths with mixed separators and case", () => {
    const platformSpy = mock:spyOn(process, "platform", "get").mockReturnValue("win32");
    try {
      const root = "C:\\Users\\User\\OpenClaw";
      const candidate = "c:/users/user/openclaw/memory/log.txt";
      (expect* toRelativeWorkspacePath(root, candidate)).is("memory\\log.txt");
    } finally {
      platformSpy.mockRestore();
    }
  });

  (deftest "rejects windows paths outside workspace root", () => {
    const platformSpy = mock:spyOn(process, "platform", "get").mockReturnValue("win32");
    try {
      const root = "C:\\Users\\User\\OpenClaw";
      const candidate = "C:\\Users\\User\\Other\\log.txt";
      (expect* () => toRelativeWorkspacePath(root, candidate)).signals-error("Path escapes workspace root");
    } finally {
      platformSpy.mockRestore();
    }
  });
});
