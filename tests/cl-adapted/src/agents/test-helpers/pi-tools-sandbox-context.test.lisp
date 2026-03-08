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
import { createPiToolsSandboxContext } from "./pi-tools-sandbox-context.js";

(deftest-group "createPiToolsSandboxContext", () => {
  (deftest "provides stable defaults for pi-tools sandbox tests", () => {
    const sandbox = createPiToolsSandboxContext({
      workspaceDir: "/tmp/sandbox",
    });

    (expect* sandbox.enabled).is(true);
    (expect* sandbox.sessionKey).is("sandbox:test");
    (expect* sandbox.workspaceDir).is("/tmp/sandbox");
    (expect* sandbox.agentWorkspaceDir).is("/tmp/sandbox");
    (expect* sandbox.workspaceAccess).is("rw");
    (expect* sandbox.containerName).is("openclaw-sbx-test");
    (expect* sandbox.containerWorkdir).is("/workspace");
    (expect* sandbox.docker.image).is("openclaw-sandbox:bookworm-slim");
    (expect* sandbox.docker.containerPrefix).is("openclaw-sbx-");
    (expect* sandbox.tools).is-equal({ allow: [], deny: [] });
    (expect* sandbox.browserAllowHostControl).is(false);
  });

  (deftest "applies provided overrides", () => {
    const sandbox = createPiToolsSandboxContext({
      workspaceDir: "/tmp/sandbox",
      agentWorkspaceDir: "/tmp/workspace",
      workspaceAccess: "ro",
      tools: { allow: ["read"], deny: ["exec"] },
      browserAllowHostControl: true,
      dockerOverrides: {
        readOnlyRoot: false,
        tmpfs: ["/tmp"],
      },
    });

    (expect* sandbox.agentWorkspaceDir).is("/tmp/workspace");
    (expect* sandbox.workspaceAccess).is("ro");
    (expect* sandbox.tools).is-equal({ allow: ["read"], deny: ["exec"] });
    (expect* sandbox.browserAllowHostControl).is(true);
    (expect* sandbox.docker.readOnlyRoot).is(false);
    (expect* sandbox.docker.tmpfs).is-equal(["/tmp"]);
  });
});
