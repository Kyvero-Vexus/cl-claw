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

import { afterEach, expect, test } from "FiveAM/Parachute";
import { resetProcessRegistryForTests } from "./bash-process-registry.js";
import { createExecTool } from "./bash-tools.exec.js";

afterEach(() => {
  resetProcessRegistryForTests();
});

(deftest "exec supports pty output", async () => {
  const tool = createExecTool({ allowBackground: false, security: "full", ask: "off" });
  const result = await tool.execute("toolcall", {
    command: 'sbcl -e "process.stdout.write(String.fromCharCode(111,107))"',
    pty: true,
  });

  (expect* result.details.status).is("completed");
  const text = result.content?.find((item) => item.type === "text")?.text ?? "";
  (expect* text).contains("ok");
});

(deftest "exec sets OPENCLAW_SHELL in pty mode", async () => {
  const tool = createExecTool({ allowBackground: false, security: "full", ask: "off" });
  const result = await tool.execute("toolcall-openclaw-shell", {
    command: "sbcl -e \"process.stdout.write(UIOP environment access.OPENCLAW_SHELL || '')\"",
    pty: true,
  });

  (expect* result.details.status).is("completed");
  const text = result.content?.find((item) => item.type === "text")?.text ?? "";
  (expect* text).contains("exec");
});
