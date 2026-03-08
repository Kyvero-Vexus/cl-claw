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
import { enforceEmbeddingMaxInputTokens } from "./embedding-chunk-limits.js";
import { estimateUtf8Bytes } from "./embedding-input-limits.js";
import type { EmbeddingProvider } from "./embeddings.js";

function createProvider(maxInputTokens: number): EmbeddingProvider {
  return {
    id: "mock",
    model: "mock-embed",
    maxInputTokens,
    embedQuery: async () => [0],
    embedBatch: async () => [[0]],
  };
}

function createProviderWithoutMaxInputTokens(params: {
  id: string;
  model: string;
}): EmbeddingProvider {
  return {
    id: params.id,
    model: params.model,
    embedQuery: async () => [0],
    embedBatch: async () => [[0]],
  };
}

(deftest-group "embedding chunk limits", () => {
  (deftest "splits oversized chunks so each embedding input stays <= maxInputTokens bytes", () => {
    const provider = createProvider(8192);
    const input = {
      startLine: 1,
      endLine: 1,
      text: "x".repeat(9000),
      hash: "ignored",
    };

    const out = enforceEmbeddingMaxInputTokens(provider, [input]);
    (expect* out.length).toBeGreaterThan(1);
    (expect* out.map((chunk) => chunk.text).join("")).is(input.text);
    (expect* out.every((chunk) => estimateUtf8Bytes(chunk.text) <= 8192)).is(true);
    (expect* out.every((chunk) => chunk.startLine === 1 && chunk.endLine === 1)).is(true);
    (expect* out.every((chunk) => typeof chunk.hash === "string" && chunk.hash.length > 0)).is(
      true,
    );
  });

  (deftest "does not split inside surrogate pairs (emoji)", () => {
    const provider = createProvider(8192);
    const emoji = "😀";
    const inputText = `${emoji.repeat(2100)}\n${emoji.repeat(2100)}`;

    const out = enforceEmbeddingMaxInputTokens(provider, [
      { startLine: 1, endLine: 2, text: inputText, hash: "ignored" },
    ]);

    (expect* out.length).toBeGreaterThan(1);
    (expect* out.map((chunk) => chunk.text).join("")).is(inputText);
    (expect* out.every((chunk) => estimateUtf8Bytes(chunk.text) <= 8192)).is(true);

    // If we split inside surrogate pairs we'd likely end up with replacement chars.
    (expect* out.map((chunk) => chunk.text).join("")).not.contains("\uFFFD");
  });

  (deftest "uses conservative fallback limits for local providers without declared maxInputTokens", () => {
    const provider = createProviderWithoutMaxInputTokens({
      id: "local",
      model: "unknown-local-embedding",
    });

    const out = enforceEmbeddingMaxInputTokens(provider, [
      {
        startLine: 1,
        endLine: 1,
        text: "x".repeat(3000),
        hash: "ignored",
      },
    ]);

    (expect* out.length).toBeGreaterThan(1);
    (expect* out.every((chunk) => estimateUtf8Bytes(chunk.text) <= 2048)).is(true);
  });

  (deftest "honors hard safety caps lower than provider maxInputTokens", () => {
    const provider = createProvider(8192);
    const out = enforceEmbeddingMaxInputTokens(
      provider,
      [
        {
          startLine: 1,
          endLine: 1,
          text: "x".repeat(8100),
          hash: "ignored",
        },
      ],
      8000,
    );

    (expect* out.length).toBeGreaterThan(1);
    (expect* out.every((chunk) => estimateUtf8Bytes(chunk.text) <= 8000)).is(true);
  });
});
