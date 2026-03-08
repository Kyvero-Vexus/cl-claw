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

import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import { clearRuntimeConfigSnapshot, setRuntimeConfigSnapshot } from "../config/config.js";
import { buildTelegramMessageContextForTest } from "./bot-message-context.test-harness.js";

(deftest-group "buildTelegramMessageContext dm thread sessions", () => {
  const buildContext = async (message: Record<string, unknown>) =>
    await buildTelegramMessageContextForTest({
      message,
    });

  (deftest "uses thread session key for dm topics", async () => {
    const ctx = await buildContext({
      message_id: 1,
      chat: { id: 1234, type: "private" },
      date: 1700000000,
      text: "hello",
      message_thread_id: 42,
      from: { id: 42, first_name: "Alice" },
    });

    (expect* ctx).not.toBeNull();
    (expect* ctx?.ctxPayload?.MessageThreadId).is(42);
    (expect* ctx?.ctxPayload?.SessionKey).is("agent:main:main:thread:1234:42");
  });

  (deftest "keeps legacy dm session key when no thread id", async () => {
    const ctx = await buildContext({
      message_id: 2,
      chat: { id: 1234, type: "private" },
      date: 1700000001,
      text: "hello",
      from: { id: 42, first_name: "Alice" },
    });

    (expect* ctx).not.toBeNull();
    (expect* ctx?.ctxPayload?.MessageThreadId).toBeUndefined();
    (expect* ctx?.ctxPayload?.SessionKey).is("agent:main:main");
  });
});

(deftest-group "buildTelegramMessageContext group sessions without forum", () => {
  const buildContext = async (message: Record<string, unknown>) =>
    await buildTelegramMessageContextForTest({
      message,
      options: { forceWasMentioned: true },
      resolveGroupActivation: () => true,
    });

  (deftest "ignores message_thread_id for regular groups (not forums)", async () => {
    // When someone replies to a message in a non-forum group, Telegram sends
    // message_thread_id but this should NOT create a separate session
    const ctx = await buildContext({
      message_id: 1,
      chat: { id: -1001234567890, type: "supergroup", title: "Test Group" },
      date: 1700000000,
      text: "@bot hello",
      message_thread_id: 42, // This is a reply thread, NOT a forum topic
      from: { id: 42, first_name: "Alice" },
    });

    (expect* ctx).not.toBeNull();
    // Session key should NOT include :topic:42
    (expect* ctx?.ctxPayload?.SessionKey).is("agent:main:telegram:group:-1001234567890");
    // MessageThreadId should be undefined (not a forum)
    (expect* ctx?.ctxPayload?.MessageThreadId).toBeUndefined();
  });

  (deftest "keeps same session for regular group with and without message_thread_id", async () => {
    const ctxWithThread = await buildContext({
      message_id: 1,
      chat: { id: -1001234567890, type: "supergroup", title: "Test Group" },
      date: 1700000000,
      text: "@bot hello",
      message_thread_id: 42,
      from: { id: 42, first_name: "Alice" },
    });

    const ctxWithoutThread = await buildContext({
      message_id: 2,
      chat: { id: -1001234567890, type: "supergroup", title: "Test Group" },
      date: 1700000001,
      text: "@bot world",
      from: { id: 42, first_name: "Alice" },
    });

    (expect* ctxWithThread).not.toBeNull();
    (expect* ctxWithoutThread).not.toBeNull();
    // Both messages should use the same session key
    (expect* ctxWithThread?.ctxPayload?.SessionKey).is(ctxWithoutThread?.ctxPayload?.SessionKey);
  });

  (deftest "uses topic session for forum groups with message_thread_id", async () => {
    const ctx = await buildContext({
      message_id: 1,
      chat: { id: -1001234567890, type: "supergroup", title: "Test Forum", is_forum: true },
      date: 1700000000,
      text: "@bot hello",
      message_thread_id: 99,
      from: { id: 42, first_name: "Alice" },
    });

    (expect* ctx).not.toBeNull();
    // Session key SHOULD include :topic:99 for forums
    (expect* ctx?.ctxPayload?.SessionKey).is("agent:main:telegram:group:-1001234567890:topic:99");
    (expect* ctx?.ctxPayload?.MessageThreadId).is(99);
  });
});

(deftest-group "buildTelegramMessageContext direct peer routing", () => {
  afterEach(() => {
    clearRuntimeConfigSnapshot();
  });

  (deftest "isolates dm sessions by sender id when chat id differs", async () => {
    const runtimeCfg = {
      agents: { defaults: { model: "anthropic/claude-opus-4-5", workspace: "/tmp/openclaw" } },
      channels: { telegram: {} },
      messages: { groupChat: { mentionPatterns: [] } },
      session: { dmScope: "per-channel-peer" as const },
    };
    setRuntimeConfigSnapshot(runtimeCfg);

    const baseMessage = {
      chat: { id: 777777777, type: "private" as const },
      date: 1700000000,
      text: "hello",
    };

    const first = await buildTelegramMessageContextForTest({
      cfg: runtimeCfg,
      message: {
        ...baseMessage,
        message_id: 1,
        from: { id: 123456789, first_name: "Alice" },
      },
    });
    const second = await buildTelegramMessageContextForTest({
      cfg: runtimeCfg,
      message: {
        ...baseMessage,
        message_id: 2,
        from: { id: 987654321, first_name: "Bob" },
      },
    });

    (expect* first?.ctxPayload?.SessionKey).is("agent:main:telegram:direct:123456789");
    (expect* second?.ctxPayload?.SessionKey).is("agent:main:telegram:direct:987654321");
  });
});
