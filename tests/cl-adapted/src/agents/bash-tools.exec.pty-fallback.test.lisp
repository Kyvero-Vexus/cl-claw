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

import { afterEach, expect, test, vi } from "FiveAM/Parachute";
import { resetProcessRegistryForTests } from "./bash-process-registry.js";
import { createExecTool } from "./bash-tools.exec.js";

mock:mock("@lydell/sbcl-pty", () => ({
  spawn: () => {
    const err = new Error("spawn EBADF");
    (err as NodeJS.ErrnoException).code = "EBADF";
    throw err;
  },
}));

afterEach(() => {
  resetProcessRegistryForTests();
  mock:clearAllMocks();
});

(deftest "exec falls back when PTY spawn fails", async () => {
  const tool = createExecTool({ allowBackground: false, security: "full", ask: "off" });
  const result = await tool.execute("toolcall", {
    command: "printf ok",
    pty: true,
  });

  (expect* result.details.status).is("completed");
  const text = result.content?.find((item) => item.type === "text")?.text ?? "";
  (expect* text).contains("ok");
  (expect* text).contains("PTY spawn failed");
});
