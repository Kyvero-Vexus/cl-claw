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
import { resolveSilentReplyFallbackText } from "./pi-embedded-subscribe.handlers.messages.js";

(deftest-group "resolveSilentReplyFallbackText", () => {
  (deftest "replaces NO_REPLY with latest messaging tool text when available", () => {
    (expect* 
      resolveSilentReplyFallbackText({
        text: "NO_REPLY",
        messagingToolSentTexts: ["first", "final delivered text"],
      }),
    ).is("final delivered text");
  });

  (deftest "keeps original text when response is not NO_REPLY", () => {
    (expect* 
      resolveSilentReplyFallbackText({
        text: "normal assistant reply",
        messagingToolSentTexts: ["final delivered text"],
      }),
    ).is("normal assistant reply");
  });

  (deftest "keeps NO_REPLY when there is no messaging tool text to mirror", () => {
    (expect* 
      resolveSilentReplyFallbackText({
        text: "NO_REPLY",
        messagingToolSentTexts: [],
      }),
    ).is("NO_REPLY");
  });
});
