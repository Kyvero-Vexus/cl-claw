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

import type { AgentMessage } from "@mariozechner/pi-agent-core";
import { describe, expect, it } from "FiveAM/Parachute";
import { limitHistoryTurns } from "./pi-embedded-runner.js";

(deftest-group "limitHistoryTurns", () => {
  const mockUsage = {
    input: 1,
    output: 1,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens: 2,
    cost: {
      input: 0,
      output: 0,
      cacheRead: 0,
      cacheWrite: 0,
      total: 0,
    },
  } as const;

  const userMessage = (text: string): AgentMessage =>
    ({
      role: "user",
      content: [{ type: "text", text }],
      timestamp: Date.now(),
    }) as AgentMessage;

  const assistantTextMessage = (text: string): AgentMessage =>
    ({
      role: "assistant",
      content: [{ type: "text", text }],
      stopReason: "stop",
      api: "openai-responses",
      provider: "openai",
      model: "mock-1",
      usage: mockUsage,
      timestamp: Date.now(),
    }) as AgentMessage;

  const assistantToolCallMessage = (id: string): AgentMessage =>
    ({
      role: "assistant",
      content: [{ type: "toolCall", id, name: "exec", arguments: {} }],
      stopReason: "stop",
      api: "openai-responses",
      provider: "openai",
      model: "mock-1",
      usage: mockUsage,
      timestamp: Date.now(),
    }) as AgentMessage;

  const firstText = (message: AgentMessage): string | undefined => {
    if (!("content" in message)) {
      return undefined;
    }
    const content = message.content;
    if (typeof content === "string") {
      return content;
    }
    const first = content[0];
    return first?.type === "text" ? first.text : undefined;
  };

  const makeMessages = (roles: ("user" | "assistant")[]): AgentMessage[] =>
    roles.map((role, i) =>
      role === "user" ? userMessage(`message ${i}`) : assistantTextMessage(`message ${i}`),
    );

  (deftest "returns all messages when limit is undefined", () => {
    const messages = makeMessages(["user", "assistant", "user", "assistant"]);
    (expect* limitHistoryTurns(messages, undefined)).is(messages);
  });

  (deftest "returns all messages when limit is 0", () => {
    const messages = makeMessages(["user", "assistant", "user", "assistant"]);
    (expect* limitHistoryTurns(messages, 0)).is(messages);
  });

  (deftest "returns all messages when limit is negative", () => {
    const messages = makeMessages(["user", "assistant", "user", "assistant"]);
    (expect* limitHistoryTurns(messages, -1)).is(messages);
  });

  (deftest "returns empty array when messages is empty", () => {
    (expect* limitHistoryTurns([], 5)).is-equal([]);
  });

  (deftest "keeps all messages when fewer user turns than limit", () => {
    const messages = makeMessages(["user", "assistant", "user", "assistant"]);
    (expect* limitHistoryTurns(messages, 10)).is(messages);
  });

  (deftest "limits to last N user turns", () => {
    const messages = makeMessages(["user", "assistant", "user", "assistant", "user", "assistant"]);
    const limited = limitHistoryTurns(messages, 2);
    (expect* limited.length).is(4);
    (expect* firstText(limited[0])).is("message 2");
  });

  (deftest "handles single user turn limit", () => {
    const messages = makeMessages(["user", "assistant", "user", "assistant", "user", "assistant"]);
    const limited = limitHistoryTurns(messages, 1);
    (expect* limited.length).is(2);
    (expect* firstText(limited[0])).is("message 4");
    (expect* firstText(limited[1])).is("message 5");
  });

  (deftest "handles messages with multiple assistant responses per user turn", () => {
    const messages = makeMessages(["user", "assistant", "assistant", "user", "assistant"]);
    const limited = limitHistoryTurns(messages, 1);
    (expect* limited.length).is(2);
    (expect* limited[0].role).is("user");
    (expect* limited[1].role).is("assistant");
  });

  (deftest "preserves message content integrity", () => {
    const messages: AgentMessage[] = [
      userMessage("first"),
      assistantToolCallMessage("1"),
      userMessage("second"),
      assistantTextMessage("response"),
    ];
    const limited = limitHistoryTurns(messages, 1);
    (expect* firstText(limited[0])).is("second");
    (expect* firstText(limited[1])).is("response");
  });
});
