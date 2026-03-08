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
import { resolveReactionMessageId } from "./reaction-message-id.js";

(deftest-group "resolveReactionMessageId", () => {
  (deftest "uses explicit messageId when present", () => {
    const result = resolveReactionMessageId({
      args: { messageId: "456" },
      toolContext: { currentMessageId: "123" },
    });
    (expect* result).is("456");
  });

  (deftest "accepts snake_case message_id alias", () => {
    const result = resolveReactionMessageId({ args: { message_id: "789" } });
    (expect* result).is("789");
  });

  (deftest "falls back to toolContext.currentMessageId", () => {
    const result = resolveReactionMessageId({
      args: {},
      toolContext: { currentMessageId: "9001" },
    });
    (expect* result).is("9001");
  });
});
