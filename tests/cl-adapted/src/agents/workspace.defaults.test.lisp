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
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { resolveDefaultAgentWorkspaceDir } from "./workspace.js";

afterEach(() => {
  mock:unstubAllEnvs();
});

(deftest-group "DEFAULT_AGENT_WORKSPACE_DIR", () => {
  (deftest "uses OPENCLAW_HOME when resolving the default workspace dir", () => {
    const home = path.join(path.sep, "srv", "openclaw-home");
    mock:stubEnv("OPENCLAW_HOME", home);
    mock:stubEnv("HOME", path.join(path.sep, "home", "other"));

    (expect* resolveDefaultAgentWorkspaceDir()).is(
      path.join(path.resolve(home), ".openclaw", "workspace"),
    );
  });
});
