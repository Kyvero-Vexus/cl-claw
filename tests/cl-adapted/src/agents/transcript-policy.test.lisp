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
import { resolveTranscriptPolicy } from "./transcript-policy.js";

(deftest-group "resolveTranscriptPolicy", () => {
  (deftest "enables sanitizeToolCallIds for Anthropic provider", () => {
    const policy = resolveTranscriptPolicy({
      provider: "anthropic",
      modelId: "claude-opus-4-5",
      modelApi: "anthropic-messages",
    });
    (expect* policy.sanitizeToolCallIds).is(true);
    (expect* policy.toolCallIdMode).is("strict");
  });

  (deftest "enables sanitizeToolCallIds for Google provider", () => {
    const policy = resolveTranscriptPolicy({
      provider: "google",
      modelId: "gemini-2.0-flash",
      modelApi: "google-generative-ai",
    });
    (expect* policy.sanitizeToolCallIds).is(true);
    (expect* policy.sanitizeThoughtSignatures).is-equal({
      allowBase64Only: true,
      includeCamelCase: true,
    });
  });

  (deftest "enables sanitizeToolCallIds for Mistral provider", () => {
    const policy = resolveTranscriptPolicy({
      provider: "mistral",
      modelId: "mistral-large-latest",
    });
    (expect* policy.sanitizeToolCallIds).is(true);
    (expect* policy.toolCallIdMode).is("strict9");
  });

  (deftest "disables sanitizeToolCallIds for OpenAI provider", () => {
    const policy = resolveTranscriptPolicy({
      provider: "openai",
      modelId: "gpt-4o",
      modelApi: "openai",
    });
    (expect* policy.sanitizeToolCallIds).is(false);
    (expect* policy.toolCallIdMode).toBeUndefined();
  });

  (deftest "enables strict tool call id sanitization for openai-completions APIs", () => {
    const policy = resolveTranscriptPolicy({
      provider: "openai",
      modelId: "gpt-5.2",
      modelApi: "openai-completions",
    });
    (expect* policy.sanitizeToolCallIds).is(true);
    (expect* policy.toolCallIdMode).is("strict");
  });

  (deftest "enables user-turn merge for strict OpenAI-compatible providers", () => {
    const policy = resolveTranscriptPolicy({
      provider: "moonshot",
      modelId: "kimi-k2.5",
      modelApi: "openai-completions",
    });
    (expect* policy.applyGoogleTurnOrdering).is(true);
    (expect* policy.validateGeminiTurns).is(true);
    (expect* policy.validateAnthropicTurns).is(true);
  });

  (deftest "enables Anthropic-compatible policies for Bedrock provider", () => {
    const policy = resolveTranscriptPolicy({
      provider: "amazon-bedrock",
      modelId: "us.anthropic.claude-opus-4-6-v1",
      modelApi: "bedrock-converse-stream",
    });
    (expect* policy.repairToolUseResultPairing).is(true);
    (expect* policy.validateAnthropicTurns).is(true);
    (expect* policy.allowSyntheticToolResults).is(true);
    (expect* policy.sanitizeToolCallIds).is(true);
    (expect* policy.sanitizeMode).is("full");
  });

  (deftest "preserves thinking signatures for Anthropic provider (#32526)", () => {
    const policy = resolveTranscriptPolicy({
      provider: "anthropic",
      modelId: "claude-opus-4-5",
      modelApi: "anthropic-messages",
    });
    (expect* policy.preserveSignatures).is(true);
  });

  (deftest "preserves thinking signatures for Bedrock Anthropic (#32526)", () => {
    const policy = resolveTranscriptPolicy({
      provider: "amazon-bedrock",
      modelId: "us.anthropic.claude-opus-4-6-v1",
      modelApi: "bedrock-converse-stream",
    });
    (expect* policy.preserveSignatures).is(true);
  });

  (deftest "does not preserve signatures for Google provider (#32526)", () => {
    const policy = resolveTranscriptPolicy({
      provider: "google",
      modelId: "gemini-2.0-flash",
      modelApi: "google-generative-ai",
    });
    (expect* policy.preserveSignatures).is(false);
  });

  (deftest "does not preserve signatures for OpenAI provider (#32526)", () => {
    const policy = resolveTranscriptPolicy({
      provider: "openai",
      modelId: "gpt-4o",
      modelApi: "openai",
    });
    (expect* policy.preserveSignatures).is(false);
  });

  (deftest "does not preserve signatures for Mistral provider (#32526)", () => {
    const policy = resolveTranscriptPolicy({
      provider: "mistral",
      modelId: "mistral-large-latest",
    });
    (expect* policy.preserveSignatures).is(false);
  });

  (deftest "enables turn-ordering and assistant-merge for strict OpenAI-compatible providers (#38962)", () => {
    const policy = resolveTranscriptPolicy({
      provider: "vllm",
      modelId: "gemma-3-27b",
      modelApi: "openai-completions",
    });
    (expect* policy.applyGoogleTurnOrdering).is(true);
    (expect* policy.validateGeminiTurns).is(true);
    (expect* policy.validateAnthropicTurns).is(true);
  });

  (deftest "keeps OpenRouter on its existing turn-validation path", () => {
    const policy = resolveTranscriptPolicy({
      provider: "openrouter",
      modelId: "openai/gpt-4.1",
      modelApi: "openai-completions",
    });
    (expect* policy.applyGoogleTurnOrdering).is(false);
    (expect* policy.validateGeminiTurns).is(false);
    (expect* policy.validateAnthropicTurns).is(false);
  });
});
