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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { loadConfig } from "../config/config.js";
import { buildTelegramMessageContextForTest } from "./bot-message-context.test-harness.js";

const { defaultRouteConfig } = mock:hoisted(() => ({
  defaultRouteConfig: {
    agents: {
      list: [{ id: "main", default: true }, { id: "zu" }, { id: "q" }, { id: "support" }],
    },
    channels: { telegram: {} },
    messages: { groupChat: { mentionPatterns: [] } },
  },
}));

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: mock:fn(() => defaultRouteConfig),
  };
});

(deftest-group "buildTelegramMessageContext per-topic agentId routing", () => {
  function buildForumMessage(threadId = 3) {
    return {
      message_id: 1,
      chat: {
        id: -1001234567890,
        type: "supergroup" as const,
        title: "Forum",
        is_forum: true,
      },
      date: 1700000000,
      text: "@bot hello",
      message_thread_id: threadId,
      from: { id: 42, first_name: "Alice" },
    };
  }

  async function buildForumContext(params: {
    threadId?: number;
    topicConfig?: Record<string, unknown>;
  }) {
    return await buildTelegramMessageContextForTest({
      message: buildForumMessage(params.threadId),
      options: { forceWasMentioned: true },
      resolveGroupActivation: () => true,
      resolveTelegramGroupConfig: () => ({
        groupConfig: { requireMention: false },
        ...(params.topicConfig ? { topicConfig: params.topicConfig } : {}),
      }),
    });
  }

  beforeEach(() => {
    mock:mocked(loadConfig).mockReturnValue(defaultRouteConfig as never);
  });

  (deftest "uses group-level agent when no topic agentId is set", async () => {
    const ctx = await buildForumContext({ topicConfig: { systemPrompt: "Be nice" } });

    (expect* ctx).not.toBeNull();
    (expect* ctx?.ctxPayload?.SessionKey).is("agent:main:telegram:group:-1001234567890:topic:3");
  });

  (deftest "routes to topic-specific agent when agentId is set", async () => {
    const ctx = await buildForumContext({
      topicConfig: { agentId: "zu", systemPrompt: "I am Zu" },
    });

    (expect* ctx).not.toBeNull();
    (expect* ctx?.ctxPayload?.SessionKey).contains("agent:zu:");
    (expect* ctx?.ctxPayload?.SessionKey).contains("telegram:group:-1001234567890:topic:3");
  });

  (deftest "different topics route to different agents", async () => {
    const buildForTopic = async (threadId: number, agentId: string) =>
      await buildForumContext({ threadId, topicConfig: { agentId } });

    const ctxA = await buildForTopic(1, "main");
    const ctxB = await buildForTopic(3, "zu");
    const ctxC = await buildForTopic(5, "q");

    (expect* ctxA?.ctxPayload?.SessionKey).contains("agent:main:");
    (expect* ctxB?.ctxPayload?.SessionKey).contains("agent:zu:");
    (expect* ctxC?.ctxPayload?.SessionKey).contains("agent:q:");

    (expect* ctxA?.ctxPayload?.SessionKey).not.is(ctxB?.ctxPayload?.SessionKey);
    (expect* ctxB?.ctxPayload?.SessionKey).not.is(ctxC?.ctxPayload?.SessionKey);
  });

  (deftest "ignores whitespace-only agentId and uses group-level agent", async () => {
    const ctx = await buildForumContext({
      topicConfig: { agentId: "   ", systemPrompt: "Be nice" },
    });

    (expect* ctx).not.toBeNull();
    (expect* ctx?.ctxPayload?.SessionKey).contains("agent:main:");
  });

  (deftest "falls back to default agent when topic agentId does not exist", async () => {
    mock:mocked(loadConfig).mockReturnValue({
      agents: {
        list: [{ id: "main", default: true }, { id: "zu" }],
      },
      channels: { telegram: {} },
      messages: { groupChat: { mentionPatterns: [] } },
    } as never);

    const ctx = await buildForumContext({ topicConfig: { agentId: "ghost" } });

    (expect* ctx).not.toBeNull();
    (expect* ctx?.ctxPayload?.SessionKey).contains("agent:main:");
  });

  (deftest "routes DM topic to specific agent when agentId is set", async () => {
    const ctx = await buildTelegramMessageContextForTest({
      message: {
        message_id: 1,
        chat: {
          id: 123456789,
          type: "private",
        },
        date: 1700000000,
        text: "@bot hello",
        message_thread_id: 99,
        from: { id: 42, first_name: "Alice" },
      },
      options: { forceWasMentioned: true },
      resolveGroupActivation: () => true,
      resolveTelegramGroupConfig: () => ({
        groupConfig: { requireMention: false },
        topicConfig: { agentId: "support", systemPrompt: "I am support" },
      }),
    });

    (expect* ctx).not.toBeNull();
    (expect* ctx?.ctxPayload?.SessionKey).contains("agent:support:");
  });
});
