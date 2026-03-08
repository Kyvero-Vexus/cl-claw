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
import { castAgentMessages } from "./test-helpers/agent-message-fixtures.js";
import {
  isValidCloudCodeAssistToolId,
  sanitizeToolCallIdsForCloudCodeAssist,
} from "./tool-call-id.js";

const buildDuplicateIdCollisionInput = () =>
  castAgentMessages([
    {
      role: "assistant",
      content: [
        { type: "toolCall", id: "call_a|b", name: "read", arguments: {} },
        { type: "toolCall", id: "call_a:b", name: "read", arguments: {} },
      ],
    },
    {
      role: "toolResult",
      toolCallId: "call_a|b",
      toolName: "read",
      content: [{ type: "text", text: "one" }],
    },
    {
      role: "toolResult",
      toolCallId: "call_a:b",
      toolName: "read",
      content: [{ type: "text", text: "two" }],
    },
  ]);

function expectCollisionIdsRemainDistinct(
  out: AgentMessage[],
  mode: "strict" | "strict9",
): { aId: string; bId: string } {
  const assistant = out[0] as Extract<AgentMessage, { role: "assistant" }>;
  const a = assistant.content?.[0] as { id?: string };
  const b = assistant.content?.[1] as { id?: string };
  (expect* typeof a.id).is("string");
  (expect* typeof b.id).is("string");
  (expect* a.id).not.is(b.id);
  (expect* isValidCloudCodeAssistToolId(a.id as string, mode)).is(true);
  (expect* isValidCloudCodeAssistToolId(b.id as string, mode)).is(true);

  const r1 = out[1] as Extract<AgentMessage, { role: "toolResult" }>;
  const r2 = out[2] as Extract<AgentMessage, { role: "toolResult" }>;
  (expect* r1.toolCallId).is(a.id);
  (expect* r2.toolCallId).is(b.id);
  return { aId: a.id as string, bId: b.id as string };
}

function expectSingleToolCallRewrite(
  out: AgentMessage[],
  expectedId: string,
  mode: "strict" | "strict9",
): void {
  const assistant = out[0] as Extract<AgentMessage, { role: "assistant" }>;
  const toolCall = assistant.content?.[0] as { id?: string };
  (expect* toolCall.id).is(expectedId);
  (expect* isValidCloudCodeAssistToolId(toolCall.id as string, mode)).is(true);

  const result = out[1] as Extract<AgentMessage, { role: "toolResult" }>;
  (expect* result.toolCallId).is(toolCall.id);
}

(deftest-group "sanitizeToolCallIdsForCloudCodeAssist", () => {
  (deftest-group "strict mode (default)", () => {
    (deftest "is a no-op for already-valid non-colliding IDs", () => {
      const input = castAgentMessages([
        {
          role: "assistant",
          content: [{ type: "toolCall", id: "call1", name: "read", arguments: {} }],
        },
        {
          role: "toolResult",
          toolCallId: "call1",
          toolName: "read",
          content: [{ type: "text", text: "ok" }],
        },
      ]);

      const out = sanitizeToolCallIdsForCloudCodeAssist(input);
      (expect* out).is(input);
    });

    (deftest "strips non-alphanumeric characters from tool call IDs", () => {
      const input = castAgentMessages([
        {
          role: "assistant",
          content: [{ type: "toolCall", id: "call|item:123", name: "read", arguments: {} }],
        },
        {
          role: "toolResult",
          toolCallId: "call|item:123",
          toolName: "read",
          content: [{ type: "text", text: "ok" }],
        },
      ]);

      const out = sanitizeToolCallIdsForCloudCodeAssist(input);
      (expect* out).not.is(input);
      // Strict mode strips all non-alphanumeric characters
      expectSingleToolCallRewrite(out, "callitem123", "strict");
    });

    (deftest "avoids collisions when sanitization would produce duplicate IDs", () => {
      const input = buildDuplicateIdCollisionInput();

      const out = sanitizeToolCallIdsForCloudCodeAssist(input);
      (expect* out).not.is(input);
      expectCollisionIdsRemainDistinct(out, "strict");
    });

    (deftest "caps tool call IDs at 40 chars while preserving uniqueness", () => {
      const longA = `call_${"a".repeat(60)}`;
      const longB = `call_${"a".repeat(59)}b`;
      const input = castAgentMessages([
        {
          role: "assistant",
          content: [
            { type: "toolCall", id: longA, name: "read", arguments: {} },
            { type: "toolCall", id: longB, name: "read", arguments: {} },
          ],
        },
        {
          role: "toolResult",
          toolCallId: longA,
          toolName: "read",
          content: [{ type: "text", text: "one" }],
        },
        {
          role: "toolResult",
          toolCallId: longB,
          toolName: "read",
          content: [{ type: "text", text: "two" }],
        },
      ]);

      const out = sanitizeToolCallIdsForCloudCodeAssist(input);
      const { aId, bId } = expectCollisionIdsRemainDistinct(out, "strict");
      (expect* aId.length).toBeLessThanOrEqual(40);
      (expect* bId.length).toBeLessThanOrEqual(40);
    });
  });

  (deftest-group "strict mode (alphanumeric only)", () => {
    (deftest "strips underscores and hyphens from tool call IDs", () => {
      const input = castAgentMessages([
        {
          role: "assistant",
          content: [
            {
              type: "toolCall",
              id: "whatsapp_login_1768799841527_1",
              name: "login",
              arguments: {},
            },
          ],
        },
        {
          role: "toolResult",
          toolCallId: "whatsapp_login_1768799841527_1",
          toolName: "login",
          content: [{ type: "text", text: "ok" }],
        },
      ]);

      const out = sanitizeToolCallIdsForCloudCodeAssist(input, "strict");
      (expect* out).not.is(input);
      // Strict mode strips all non-alphanumeric characters
      expectSingleToolCallRewrite(out, "whatsapplogin17687998415271", "strict");
    });

    (deftest "avoids collisions with alphanumeric-only suffixes", () => {
      const input = buildDuplicateIdCollisionInput();

      const out = sanitizeToolCallIdsForCloudCodeAssist(input, "strict");
      (expect* out).not.is(input);
      const { aId, bId } = expectCollisionIdsRemainDistinct(out, "strict");
      // Should not contain underscores or hyphens
      (expect* aId).not.toMatch(/[_-]/);
      (expect* bId).not.toMatch(/[_-]/);
    });
  });

  (deftest-group "strict9 mode (Mistral tool call IDs)", () => {
    (deftest "is a no-op for already-valid 9-char alphanumeric IDs", () => {
      const input = castAgentMessages([
        {
          role: "assistant",
          content: [{ type: "toolCall", id: "abc123XYZ", name: "read", arguments: {} }],
        },
        {
          role: "toolResult",
          toolCallId: "abc123XYZ",
          toolName: "read",
          content: [{ type: "text", text: "ok" }],
        },
      ]);

      const out = sanitizeToolCallIdsForCloudCodeAssist(input, "strict9");
      (expect* out).is(input);
    });

    (deftest "enforces alphanumeric IDs with length 9", () => {
      const input = castAgentMessages([
        {
          role: "assistant",
          content: [
            { type: "toolCall", id: "call_abc|item:123", name: "read", arguments: {} },
            { type: "toolCall", id: "call_abc|item:456", name: "read", arguments: {} },
          ],
        },
        {
          role: "toolResult",
          toolCallId: "call_abc|item:123",
          toolName: "read",
          content: [{ type: "text", text: "one" }],
        },
        {
          role: "toolResult",
          toolCallId: "call_abc|item:456",
          toolName: "read",
          content: [{ type: "text", text: "two" }],
        },
      ]);

      const out = sanitizeToolCallIdsForCloudCodeAssist(input, "strict9");
      (expect* out).not.is(input);
      const { aId, bId } = expectCollisionIdsRemainDistinct(out, "strict9");
      (expect* aId.length).is(9);
      (expect* bId.length).is(9);
    });
  });
});
