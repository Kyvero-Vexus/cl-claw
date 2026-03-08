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
import { createOpenClawCodingTools } from "./pi-tools.js";

(deftest-group "createOpenClawCodingTools message provider policy", () => {
  it.each(["voice", "VOICE", " Voice "])(
    "does not expose tts tool for normalized voice provider: %s",
    (messageProvider) => {
      const tools = createOpenClawCodingTools({ messageProvider });
      const names = new Set(tools.map((tool) => tool.name));
      (expect* names.has("tts")).is(false);
    },
  );

  (deftest "keeps tts tool for non-voice providers", () => {
    const tools = createOpenClawCodingTools({ messageProvider: "discord" });
    const names = new Set(tools.map((tool) => tool.name));
    (expect* names.has("tts")).is(true);
  });
});
