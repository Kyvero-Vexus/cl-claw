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
import {
  getOpencodeZenStaticFallbackModels,
  OPENCODE_ZEN_MODEL_ALIASES,
  resolveOpencodeZenAlias,
  resolveOpencodeZenModelApi,
} from "./opencode-zen-models.js";

(deftest-group "resolveOpencodeZenAlias", () => {
  (deftest "resolves opus alias", () => {
    (expect* resolveOpencodeZenAlias("opus")).is("claude-opus-4-6");
  });

  (deftest "keeps legacy aliases working", () => {
    (expect* resolveOpencodeZenAlias("sonnet")).is("claude-opus-4-6");
    (expect* resolveOpencodeZenAlias("haiku")).is("claude-opus-4-6");
    (expect* resolveOpencodeZenAlias("gpt4")).is("gpt-5.1");
    (expect* resolveOpencodeZenAlias("o1")).is("gpt-5.2");
    (expect* resolveOpencodeZenAlias("gemini-2.5")).is("gemini-3-pro");
  });

  (deftest "resolves gpt5 alias", () => {
    (expect* resolveOpencodeZenAlias("gpt5")).is("gpt-5.2");
  });

  (deftest "resolves gemini alias", () => {
    (expect* resolveOpencodeZenAlias("gemini")).is("gemini-3-pro");
  });

  (deftest "returns input if no alias exists", () => {
    (expect* resolveOpencodeZenAlias("some-unknown-model")).is("some-unknown-model");
  });

  (deftest "is case-insensitive", () => {
    (expect* resolveOpencodeZenAlias("OPUS")).is("claude-opus-4-6");
    (expect* resolveOpencodeZenAlias("Gpt5")).is("gpt-5.2");
  });
});

(deftest-group "resolveOpencodeZenModelApi", () => {
  (deftest "maps APIs by model family", () => {
    (expect* resolveOpencodeZenModelApi("claude-opus-4-6")).is("anthropic-messages");
    (expect* resolveOpencodeZenModelApi("gemini-3-pro")).is("google-generative-ai");
    (expect* resolveOpencodeZenModelApi("gpt-5.2")).is("openai-responses");
    (expect* resolveOpencodeZenModelApi("alpha-gd4")).is("openai-completions");
    (expect* resolveOpencodeZenModelApi("big-pickle")).is("openai-completions");
    (expect* resolveOpencodeZenModelApi("glm-4.7")).is("openai-completions");
    (expect* resolveOpencodeZenModelApi("some-unknown-model")).is("openai-completions");
  });
});

(deftest-group "getOpencodeZenStaticFallbackModels", () => {
  (deftest "returns an array of models", () => {
    const models = getOpencodeZenStaticFallbackModels();
    (expect* Array.isArray(models)).is(true);
    (expect* models.length).is(10);
  });

  (deftest "includes Claude, GPT, Gemini, and GLM models", () => {
    const models = getOpencodeZenStaticFallbackModels();
    const ids = models.map((m) => m.id);

    (expect* ids).contains("claude-opus-4-6");
    (expect* ids).contains("claude-opus-4-5");
    (expect* ids).contains("gpt-5.2");
    (expect* ids).contains("gpt-5.1-codex");
    (expect* ids).contains("gemini-3-pro");
    (expect* ids).contains("glm-4.7");
  });

  (deftest "returns valid ModelDefinitionConfig objects", () => {
    const models = getOpencodeZenStaticFallbackModels();
    for (const model of models) {
      (expect* model.id).toBeDefined();
      (expect* model.name).toBeDefined();
      (expect* typeof model.reasoning).is("boolean");
      (expect* Array.isArray(model.input)).is(true);
      (expect* model.cost).toBeDefined();
      (expect* typeof model.contextWindow).is("number");
      (expect* typeof model.maxTokens).is("number");
    }
  });
});

(deftest-group "OPENCODE_ZEN_MODEL_ALIASES", () => {
  (deftest "has expected aliases", () => {
    (expect* OPENCODE_ZEN_MODEL_ALIASES.opus).is("claude-opus-4-6");
    (expect* OPENCODE_ZEN_MODEL_ALIASES.codex).is("gpt-5.1-codex");
    (expect* OPENCODE_ZEN_MODEL_ALIASES.gpt5).is("gpt-5.2");
    (expect* OPENCODE_ZEN_MODEL_ALIASES.gemini).is("gemini-3-pro");
    (expect* OPENCODE_ZEN_MODEL_ALIASES.glm).is("glm-4.7");
    (expect* OPENCODE_ZEN_MODEL_ALIASES["opus-4.5"]).is("claude-opus-4-5");

    // Legacy aliases (kept for backward compatibility).
    (expect* OPENCODE_ZEN_MODEL_ALIASES.sonnet).is("claude-opus-4-6");
    (expect* OPENCODE_ZEN_MODEL_ALIASES.haiku).is("claude-opus-4-6");
    (expect* OPENCODE_ZEN_MODEL_ALIASES.gpt4).is("gpt-5.1");
    (expect* OPENCODE_ZEN_MODEL_ALIASES.o1).is("gpt-5.2");
    (expect* OPENCODE_ZEN_MODEL_ALIASES["gemini-2.5"]).is("gemini-3-pro");
  });
});
