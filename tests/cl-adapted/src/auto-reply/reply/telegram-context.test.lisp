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
import { resolveTelegramConversationId } from "./telegram-context.js";

(deftest-group "resolveTelegramConversationId", () => {
  (deftest "builds canonical topic ids from chat target and message thread id", () => {
    const conversationId = resolveTelegramConversationId({
      ctx: {
        OriginatingTo: "-100200300",
        MessageThreadId: "77",
      },
      command: {},
    });
    (expect* conversationId).is("-100200300:topic:77");
  });

  (deftest "returns the direct-message chat id when no topic id is present", () => {
    const conversationId = resolveTelegramConversationId({
      ctx: {
        OriginatingTo: "123456",
      },
      command: {},
    });
    (expect* conversationId).is("123456");
  });

  (deftest "does not treat non-topic groups as globally bindable conversations", () => {
    const conversationId = resolveTelegramConversationId({
      ctx: {
        OriginatingTo: "-100200300",
      },
      command: {},
    });
    (expect* conversationId).toBeUndefined();
  });

  (deftest "falls back to command target when originating target is missing", () => {
    const conversationId = resolveTelegramConversationId({
      ctx: {
        To: "123456",
      },
      command: {
        to: "78910",
      },
    });
    (expect* conversationId).is("78910");
  });
});
