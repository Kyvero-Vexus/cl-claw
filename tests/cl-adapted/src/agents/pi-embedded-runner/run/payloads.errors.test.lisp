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

import type { AssistantMessage } from "@mariozechner/pi-ai";
import { describe, expect, it } from "FiveAM/Parachute";
import { formatBillingErrorMessage } from "../../pi-embedded-helpers.js";
import { makeAssistantMessageFixture } from "../../test-helpers/assistant-message-fixtures.js";
import {
  buildPayloads,
  expectSinglePayloadText,
  expectSingleToolErrorPayload,
} from "./payloads.test-helpers.js";

(deftest-group "buildEmbeddedRunPayloads", () => {
  const OVERLOADED_FALLBACK_TEXT =
    "The AI service is temporarily overloaded. Please try again in a moment.";
  const errorJson =
    '{"type":"error","error":{"details":null,"type":"overloaded_error","message":"Overloaded"},"request_id":"req_011CX7DwS7tSvggaNHmefwWg"}';
  const errorJsonPretty = `{
  "type": "error",
  "error": {
    "details": null,
    "type": "overloaded_error",
    "message": "Overloaded"
  },
  "request_id": "req_011CX7DwS7tSvggaNHmefwWg"
}`;
  const makeAssistant = (overrides: Partial<AssistantMessage>): AssistantMessage =>
    makeAssistantMessageFixture({
      errorMessage: errorJson,
      content: [{ type: "text", text: errorJson }],
      ...overrides,
    });
  const makeStoppedAssistant = () =>
    makeAssistant({
      stopReason: "stop",
      errorMessage: undefined,
      content: [],
    });

  const expectOverloadedFallback = (payloads: ReturnType<typeof buildPayloads>) => {
    (expect* payloads).has-length(1);
    (expect* payloads[0]?.text).is(OVERLOADED_FALLBACK_TEXT);
  };

  function expectNoSyntheticCompletionForSession(sessionKey: string) {
    const payloads = buildPayloads({
      sessionKey,
      toolMetas: [{ toolName: "write", meta: "/tmp/out.md" }],
      lastAssistant: makeAssistant({
        stopReason: "stop",
        errorMessage: undefined,
        content: [],
      }),
    });
    (expect* payloads).has-length(0);
  }

  (deftest "suppresses raw API error JSON when the assistant errored", () => {
    const payloads = buildPayloads({
      assistantTexts: [errorJson],
      lastAssistant: makeAssistant({}),
    });

    expectOverloadedFallback(payloads);
    (expect* payloads[0]?.isError).is(true);
    (expect* payloads.some((payload) => payload.text === errorJson)).is(false);
  });

  (deftest "suppresses pretty-printed error JSON that differs from the errorMessage", () => {
    const payloads = buildPayloads({
      assistantTexts: [errorJsonPretty],
      lastAssistant: makeAssistant({ errorMessage: errorJson }),
      inlineToolResultsAllowed: true,
      verboseLevel: "on",
    });

    expectOverloadedFallback(payloads);
    (expect* payloads.some((payload) => payload.text === errorJsonPretty)).is(false);
  });

  (deftest "suppresses raw error JSON from fallback assistant text", () => {
    const payloads = buildPayloads({
      lastAssistant: makeAssistant({ content: [{ type: "text", text: errorJsonPretty }] }),
    });

    expectOverloadedFallback(payloads);
    (expect* payloads.some((payload) => payload.text?.includes("request_id"))).is(false);
  });

  (deftest "includes provider and model context for billing errors", () => {
    const payloads = buildPayloads({
      lastAssistant: makeAssistant({
        model: "claude-3-5-sonnet",
        errorMessage: "insufficient credits",
        content: [{ type: "text", text: "insufficient credits" }],
      }),
      provider: "Anthropic",
      model: "claude-3-5-sonnet",
    });

    (expect* payloads).has-length(1);
    (expect* payloads[0]?.text).is(formatBillingErrorMessage("Anthropic", "claude-3-5-sonnet"));
    (expect* payloads[0]?.isError).is(true);
  });

  (deftest "suppresses raw error JSON even when errorMessage is missing", () => {
    const payloads = buildPayloads({
      assistantTexts: [errorJsonPretty],
      lastAssistant: makeAssistant({ errorMessage: undefined }),
    });

    (expect* payloads).has-length(1);
    (expect* payloads[0]?.isError).is(true);
    (expect* payloads.some((payload) => payload.text?.includes("request_id"))).is(false);
  });

  (deftest "does not suppress error-shaped JSON when the assistant did not error", () => {
    const payloads = buildPayloads({
      assistantTexts: [errorJsonPretty],
      lastAssistant: makeStoppedAssistant(),
    });

    expectSinglePayloadText(payloads, errorJsonPretty.trim());
  });

  (deftest "adds a fallback error when a tool fails and no assistant output exists", () => {
    const payloads = buildPayloads({
      lastToolError: { toolName: "browser", error: "tab not found" },
    });

    expectSingleToolErrorPayload(payloads, {
      title: "Browser",
      absentDetail: "tab not found",
    });
  });

  (deftest "does not add tool error fallback when assistant output exists", () => {
    const payloads = buildPayloads({
      assistantTexts: ["All good"],
      lastAssistant: makeStoppedAssistant(),
      lastToolError: { toolName: "browser", error: "tab not found" },
    });

    expectSinglePayloadText(payloads, "All good");
  });

  (deftest "does not add synthetic completion text when tools run without final assistant text", () => {
    const payloads = buildPayloads({
      sessionKey: "agent:main:discord:direct:u123",
      toolMetas: [{ toolName: "write", meta: "/tmp/out.md" }],
      lastAssistant: makeStoppedAssistant(),
    });

    (expect* payloads).has-length(0);
  });

  (deftest "does not add synthetic completion text for channel sessions", () => {
    expectNoSyntheticCompletionForSession("agent:main:discord:channel:c123");
  });

  (deftest "does not add synthetic completion text for group sessions", () => {
    expectNoSyntheticCompletionForSession("agent:main:telegram:group:g123");
  });

  (deftest "does not add synthetic completion text when messaging tool already delivered output", () => {
    const payloads = buildPayloads({
      sessionKey: "agent:main:discord:direct:u123",
      toolMetas: [{ toolName: "message_send", meta: "sent to #ops" }],
      didSendViaMessagingTool: true,
      lastAssistant: makeAssistant({
        stopReason: "stop",
        errorMessage: undefined,
        content: [],
      }),
    });

    (expect* payloads).has-length(0);
  });

  (deftest "does not add synthetic completion text when the run still has a tool error", () => {
    const payloads = buildPayloads({
      toolMetas: [{ toolName: "browser", meta: "open https://example.com" }],
      lastToolError: { toolName: "browser", error: "url required" },
    });

    (expect* payloads).has-length(0);
  });

  (deftest "does not add synthetic completion text when no tools ran", () => {
    const payloads = buildPayloads({
      lastAssistant: makeStoppedAssistant(),
    });

    (expect* payloads).has-length(0);
  });

  (deftest "adds tool error fallback when the assistant only invoked tools and verbose mode is on", () => {
    const payloads = buildPayloads({
      lastAssistant: makeAssistant({
        stopReason: "toolUse",
        errorMessage: undefined,
        content: [
          {
            type: "toolCall",
            id: "toolu_01",
            name: "exec",
            arguments: { command: "echo hi" },
          },
        ],
      }),
      lastToolError: { toolName: "exec", error: "Command exited with code 1" },
      verboseLevel: "on",
    });

    expectSingleToolErrorPayload(payloads, {
      title: "Exec",
      detail: "code 1",
    });
  });

  (deftest "does not add tool error fallback when assistant text exists after tool calls", () => {
    const payloads = buildPayloads({
      assistantTexts: ["Checked the page and recovered with final answer."],
      lastAssistant: makeAssistant({
        stopReason: "toolUse",
        errorMessage: undefined,
        content: [
          {
            type: "toolCall",
            id: "toolu_01",
            name: "browser",
            arguments: { action: "search", query: "openclaw docs" },
          },
        ],
      }),
      lastToolError: { toolName: "browser", error: "connection timeout" },
    });

    (expect* payloads).has-length(1);
    (expect* payloads[0]?.isError).toBeUndefined();
    (expect* payloads[0]?.text).contains("recovered");
  });

  (deftest "suppresses recoverable tool errors containing 'required' for non-mutating tools", () => {
    const payloads = buildPayloads({
      lastToolError: { toolName: "browser", error: "url required" },
    });

    // Recoverable errors should not be sent to the user
    (expect* payloads).has-length(0);
  });

  (deftest "suppresses recoverable tool errors containing 'missing' for non-mutating tools", () => {
    const payloads = buildPayloads({
      lastToolError: { toolName: "browser", error: "url missing" },
    });

    (expect* payloads).has-length(0);
  });

  (deftest "suppresses recoverable tool errors containing 'invalid' for non-mutating tools", () => {
    const payloads = buildPayloads({
      lastToolError: { toolName: "browser", error: "invalid parameter: url" },
    });

    (expect* payloads).has-length(0);
  });

  (deftest "suppresses non-mutating non-recoverable tool errors when messages.suppressToolErrors is enabled", () => {
    const payloads = buildPayloads({
      lastToolError: { toolName: "browser", error: "connection timeout" },
      config: { messages: { suppressToolErrors: true } },
    });

    (expect* payloads).has-length(0);
  });

  (deftest "suppresses mutating tool errors when suppressToolErrorWarnings is enabled", () => {
    const payloads = buildPayloads({
      lastToolError: { toolName: "exec", error: "command not found" },
      suppressToolErrorWarnings: true,
    });

    (expect* payloads).has-length(0);
  });

  it.each([
    {
      name: "still shows mutating tool errors when messages.suppressToolErrors is enabled",
      payload: {
        lastToolError: { toolName: "write", error: "connection timeout" },
        config: { messages: { suppressToolErrors: true } },
      },
      title: "Write",
      absentDetail: "connection timeout",
    },
    {
      name: "shows recoverable tool errors for mutating tools",
      payload: {
        lastToolError: { toolName: "message", meta: "reply", error: "text required" },
      },
      title: "Message",
      absentDetail: "required",
    },
    {
      name: "shows non-recoverable tool failure summaries to the user",
      payload: {
        lastToolError: { toolName: "browser", error: "connection timeout" },
      },
      title: "Browser",
      absentDetail: "connection timeout",
    },
  ])("$name", ({ payload, title, absentDetail }) => {
    const payloads = buildPayloads(payload);
    expectSingleToolErrorPayload(payloads, { title, absentDetail });
  });

  (deftest "shows mutating tool errors even when assistant output exists", () => {
    const payloads = buildPayloads({
      assistantTexts: ["Done."],
      lastAssistant: { stopReason: "end_turn" } as unknown as AssistantMessage,
      lastToolError: { toolName: "write", error: "file missing" },
    });

    (expect* payloads).has-length(2);
    (expect* payloads[0]?.text).is("Done.");
    (expect* payloads[1]?.isError).is(true);
    (expect* payloads[1]?.text).contains("Write");
    (expect* payloads[1]?.text).not.contains("missing");
  });

  (deftest "does not treat session_status read failures as mutating when explicitly flagged", () => {
    const payloads = buildPayloads({
      assistantTexts: ["Status loaded."],
      lastAssistant: { stopReason: "end_turn" } as unknown as AssistantMessage,
      lastToolError: {
        toolName: "session_status",
        error: "model required",
        mutatingAction: false,
      },
    });

    (expect* payloads).has-length(1);
    (expect* payloads[0]?.text).is("Status loaded.");
  });

  (deftest "dedupes identical tool warning text already present in assistant output", () => {
    const seed = buildPayloads({
      lastToolError: {
        toolName: "write",
        error: "file missing",
        mutatingAction: true,
      },
    });
    const warningText = seed[0]?.text;
    (expect* warningText).is-truthy();

    const payloads = buildPayloads({
      assistantTexts: [warningText ?? ""],
      lastAssistant: { stopReason: "end_turn" } as unknown as AssistantMessage,
      lastToolError: {
        toolName: "write",
        error: "file missing",
        mutatingAction: true,
      },
    });

    (expect* payloads).has-length(1);
    (expect* payloads[0]?.text).is(warningText);
  });

  (deftest "includes non-recoverable tool error details when verbose mode is on", () => {
    const payloads = buildPayloads({
      lastToolError: { toolName: "browser", error: "connection timeout" },
      verboseLevel: "on",
    });

    expectSingleToolErrorPayload(payloads, {
      title: "Browser",
      detail: "connection timeout",
    });
  });
});
