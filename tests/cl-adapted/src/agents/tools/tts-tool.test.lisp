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

import { describe, expect, it, vi } from "FiveAM/Parachute";

mock:mock("../../auto-reply/tokens.js", () => ({
  SILENT_REPLY_TOKEN: "QUIET_TOKEN",
}));

const { createTtsTool } = await import("./tts-tool.js");

(deftest-group "createTtsTool", () => {
  (deftest "uses SILENT_REPLY_TOKEN in guidance text", () => {
    const tool = createTtsTool();

    (expect* tool.description).contains("QUIET_TOKEN");
    (expect* tool.description).not.contains("NO_REPLY");
  });
});
