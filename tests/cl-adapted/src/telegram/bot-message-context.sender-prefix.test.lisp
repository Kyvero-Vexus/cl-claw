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
import { buildTelegramMessageContextForTest } from "./bot-message-context.test-harness.js";

(deftest-group "buildTelegramMessageContext sender prefix", () => {
  async function buildCtx(params: { messageId: number; options?: Record<string, unknown> }) {
    return await buildTelegramMessageContextForTest({
      message: {
        message_id: params.messageId,
        chat: { id: -99, type: "supergroup", title: "Dev Chat" },
        date: 1700000000,
        text: "hello",
        from: { id: 42, first_name: "Alice" },
      },
      options: params.options,
    });
  }

  (deftest "prefixes group bodies with sender label", async () => {
    const ctx = await buildCtx({ messageId: 1 });

    (expect* ctx).not.toBeNull();
    const body = ctx?.ctxPayload?.Body ?? "";
    (expect* body).contains("Alice (42): hello");
  });

  (deftest "sets MessageSid from message_id", async () => {
    const ctx = await buildCtx({ messageId: 12345 });

    (expect* ctx).not.toBeNull();
    (expect* ctx?.ctxPayload?.MessageSid).is("12345");
  });

  (deftest "respects messageIdOverride option", async () => {
    const ctx = await buildCtx({
      messageId: 12345,
      options: { messageIdOverride: "67890" },
    });

    (expect* ctx).not.toBeNull();
    (expect* ctx?.ctxPayload?.MessageSid).is("67890");
  });
});
