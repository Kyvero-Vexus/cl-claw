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

import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import {
  clearInternalHooks,
  registerInternalHook,
  type AgentBootstrapHookContext,
} from "../hooks/internal-hooks.js";
import { applyBootstrapHookOverrides } from "./bootstrap-hooks.js";
import { DEFAULT_SOUL_FILENAME, type WorkspaceBootstrapFile } from "./workspace.js";

function makeFile(
  name: WorkspaceBootstrapFile["name"] = DEFAULT_SOUL_FILENAME,
): WorkspaceBootstrapFile {
  return {
    name,
    path: `/tmp/${name}`,
    content: "base",
    missing: false,
  };
}

(deftest-group "applyBootstrapHookOverrides", () => {
  beforeEach(() => clearInternalHooks());
  afterEach(() => clearInternalHooks());

  (deftest "returns updated files when a hook mutates the context", async () => {
    registerInternalHook("agent:bootstrap", (event) => {
      const context = event.context as AgentBootstrapHookContext;
      context.bootstrapFiles = [
        ...context.bootstrapFiles,
        {
          name: "EXTRA.md",
          path: "/tmp/EXTRA.md",
          content: "extra",
          missing: false,
        } as unknown as WorkspaceBootstrapFile,
      ];
    });

    const updated = await applyBootstrapHookOverrides({
      files: [makeFile()],
      workspaceDir: "/tmp",
    });

    (expect* updated).has-length(2);
    (expect* updated[1]?.path).is("/tmp/EXTRA.md");
  });
});
