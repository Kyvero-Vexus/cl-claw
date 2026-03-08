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
import {
  BILLING_ERROR_USER_MESSAGE,
  formatBillingErrorMessage,
  formatAssistantErrorText,
  formatRawAssistantErrorForUi,
} from "./pi-embedded-helpers.js";
import { makeAssistantMessageFixture } from "./test-helpers/assistant-message-fixtures.js";

(deftest-group "formatAssistantErrorText", () => {
  const makeAssistantError = (errorMessage: string): AssistantMessage =>
    makeAssistantMessageFixture({
      errorMessage,
      content: [{ type: "text", text: errorMessage }],
    });

  (deftest "returns a friendly message for context overflow", () => {
    const msg = makeAssistantError("request_too_large");
    (expect* formatAssistantErrorText(msg)).contains("Context overflow");
  });
  (deftest "returns context overflow for Anthropic 'Request size exceeds model context window'", () => {
    // This is the new Anthropic error format that wasn't being detected.
    // Without the fix, this falls through to the invalidRequest regex and returns
    // "LLM request rejected: Request size exceeds model context window"
    // instead of the context overflow message, preventing auto-compaction.
    const msg = makeAssistantError(
      '{"type":"error","error":{"type":"invalid_request_error","message":"Request size exceeds model context window"}}',
    );
    (expect* formatAssistantErrorText(msg)).contains("Context overflow");
  });
  (deftest "returns context overflow for Kimi 'model token limit' errors", () => {
    const msg = makeAssistantError(
      "error, status code: 400, message: Invalid request: Your request exceeded model token limit: 262144 (requested: 291351)",
    );
    (expect* formatAssistantErrorText(msg)).contains("Context overflow");
  });
  (deftest "returns a reasoning-required message for mandatory reasoning endpoint errors", () => {
    const msg = makeAssistantError(
      "400 Reasoning is mandatory for this endpoint and cannot be disabled.",
    );
    const result = formatAssistantErrorText(msg);
    (expect* result).contains("Reasoning is required");
    (expect* result).contains("/think minimal");
    (expect* result).not.contains("Context overflow");
  });
  (deftest "returns a friendly message for Anthropic role ordering", () => {
    const msg = makeAssistantError('messages: roles must alternate between "user" and "assistant"');
    (expect* formatAssistantErrorText(msg)).contains("Message ordering conflict");
  });
  (deftest "returns a friendly message for Anthropic overload errors", () => {
    const msg = makeAssistantError(
      '{"type":"error","error":{"details":null,"type":"overloaded_error","message":"Overloaded"},"request_id":"req_123"}',
    );
    (expect* formatAssistantErrorText(msg)).is(
      "The AI service is temporarily overloaded. Please try again in a moment.",
    );
  });
  (deftest "returns a recovery hint when tool call input is missing", () => {
    const msg = makeAssistantError("tool_use.input: Field required");
    const result = formatAssistantErrorText(msg);
    (expect* result).contains("Session history looks corrupted");
    (expect* result).contains("/new");
  });
  (deftest "handles JSON-wrapped role errors", () => {
    const msg = makeAssistantError('{"error":{"message":"400 Incorrect role information"}}');
    const result = formatAssistantErrorText(msg);
    (expect* result).contains("Message ordering conflict");
    (expect* result).not.contains("400");
  });
  (deftest "suppresses raw error JSON payloads that are not otherwise classified", () => {
    const msg = makeAssistantError(
      '{"type":"error","error":{"message":"Something exploded","type":"server_error"}}',
    );
    (expect* formatAssistantErrorText(msg)).is("LLM error server_error: Something exploded");
  });
  (deftest "returns a friendly billing message for credit balance errors", () => {
    const msg = makeAssistantError("Your credit balance is too low to access the Anthropic API.");
    const result = formatAssistantErrorText(msg);
    (expect* result).is(BILLING_ERROR_USER_MESSAGE);
  });
  (deftest "returns a friendly billing message for HTTP 402 errors", () => {
    const msg = makeAssistantError("HTTP 402 Payment Required");
    const result = formatAssistantErrorText(msg);
    (expect* result).is(BILLING_ERROR_USER_MESSAGE);
  });
  (deftest "returns a friendly billing message for insufficient credits", () => {
    const msg = makeAssistantError("insufficient credits");
    const result = formatAssistantErrorText(msg);
    (expect* result).is(BILLING_ERROR_USER_MESSAGE);
  });
  (deftest "includes provider and assistant model in billing message when provider is given", () => {
    const msg = makeAssistantError("insufficient credits");
    const result = formatAssistantErrorText(msg, { provider: "Anthropic" });
    (expect* result).is(formatBillingErrorMessage("Anthropic", "test-model"));
    (expect* result).contains("Anthropic");
    (expect* result).not.contains("API provider");
  });
  (deftest "uses the active assistant model for billing message context", () => {
    const msg = makeAssistantError("insufficient credits");
    msg.model = "claude-3-5-sonnet";
    const result = formatAssistantErrorText(msg, { provider: "Anthropic" });
    (expect* result).is(formatBillingErrorMessage("Anthropic", "claude-3-5-sonnet"));
  });
  (deftest "returns generic billing message when provider is not given", () => {
    const msg = makeAssistantError("insufficient credits");
    const result = formatAssistantErrorText(msg);
    (expect* result).contains("API provider");
    (expect* result).is(BILLING_ERROR_USER_MESSAGE);
  });
  (deftest "returns a friendly message for rate limit errors", () => {
    const msg = makeAssistantError("429 rate limit reached");
    (expect* formatAssistantErrorText(msg)).contains("rate limit reached");
  });

  (deftest "returns a friendly message for empty stream chunk errors", () => {
    const msg = makeAssistantError("request ended without sending any chunks");
    (expect* formatAssistantErrorText(msg)).is("LLM request timed out.");
  });
});

(deftest-group "formatRawAssistantErrorForUi", () => {
  (deftest "renders HTTP code + type + message from Anthropic payloads", () => {
    const text = formatRawAssistantErrorForUi(
      '429 {"type":"error","error":{"type":"rate_limit_error","message":"Rate limited."},"request_id":"req_123"}',
    );

    (expect* text).contains("HTTP 429");
    (expect* text).contains("rate_limit_error");
    (expect* text).contains("Rate limited.");
    (expect* text).contains("req_123");
  });

  (deftest "renders a generic unknown error message when raw is empty", () => {
    (expect* formatRawAssistantErrorForUi("")).contains("unknown error");
  });

  (deftest "formats plain HTTP status lines", () => {
    (expect* formatRawAssistantErrorForUi("500 Internal Server Error")).is(
      "HTTP 500: Internal Server Error",
    );
  });

  (deftest "sanitizes HTML error pages into a clean unavailable message", () => {
    const htmlError = `521 <!DOCTYPE html>
<html lang="en-US">
  <head><title>Web server is down | example.com | Cloudflare</title></head>
  <body>Ray ID: abc123</body>
</html>`;

    (expect* formatRawAssistantErrorForUi(htmlError)).is(
      "The AI service is temporarily unavailable (HTTP 521). Please try again in a moment.",
    );
  });
});
