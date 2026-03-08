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

import { mkdtempSync } from "sbcl:fs";
import { tmpdir } from "sbcl:os";
import { join } from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  normalizeAntigravityModelId,
  normalizeGoogleModelId,
  normalizeProviders,
  type ProviderConfig,
} from "./models-config.providers.js";

function buildModel(id: string): NonNullable<ProviderConfig["models"]>[number] {
  return {
    id,
    name: id,
    reasoning: true,
    input: ["text"],
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow: 1,
    maxTokens: 1,
  };
}

function buildProvider(modelIds: string[]): ProviderConfig {
  return {
    baseUrl: "https://example.invalid/v1",
    api: "openai-completions",
    apiKey: "EXAMPLE_KEY", // pragma: allowlist secret
    models: modelIds.map((id) => buildModel(id)),
  };
}

(deftest-group "normalizeAntigravityModelId", () => {
  it.each(["gemini-3-pro", "gemini-3.1-pro", "gemini-3-1-pro"])(
    "adds default -low suffix to bare pro id: %s",
    (id) => {
      (expect* normalizeAntigravityModelId(id)).is(`${id}-low`);
    },
  );

  it.each([
    "gemini-3-pro-low",
    "gemini-3-pro-high",
    "gemini-3.1-flash",
    "claude-opus-4-6-thinking",
  ])("keeps already-tiered and non-pro ids unchanged: %s", (id) => {
    (expect* normalizeAntigravityModelId(id)).is(id);
  });
});

(deftest-group "normalizeGoogleModelId", () => {
  (deftest "maps the deprecated 3.1 flash alias to the real preview model", () => {
    (expect* normalizeGoogleModelId("gemini-3.1-flash")).is("gemini-3-flash-preview");
    (expect* normalizeGoogleModelId("gemini-3.1-flash-preview")).is("gemini-3-flash-preview");
  });

  (deftest "adds the preview suffix for gemini 3.1 flash-lite", () => {
    (expect* normalizeGoogleModelId("gemini-3.1-flash-lite")).is("gemini-3.1-flash-lite-preview");
  });
});

(deftest-group "google-antigravity provider normalization", () => {
  (deftest "normalizes bare gemini pro IDs only for google-antigravity providers", () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    const providers = {
      "google-antigravity": buildProvider([
        "gemini-3-pro",
        "gemini-3.1-pro",
        "gemini-3-1-pro",
        "gemini-3-pro-high",
        "claude-opus-4-6-thinking",
      ]),
      openai: buildProvider(["gpt-5"]),
    };

    const normalized = normalizeProviders({ providers, agentDir });

    (expect* normalized).not.is(providers);
    (expect* normalized?.["google-antigravity"]?.models.map((model) => model.id)).is-equal([
      "gemini-3-pro-low",
      "gemini-3.1-pro-low",
      "gemini-3-1-pro-low",
      "gemini-3-pro-high",
      "claude-opus-4-6-thinking",
    ]);
    (expect* normalized?.openai).is(providers.openai);
  });

  (deftest "returns original providers object when no antigravity IDs need normalization", () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    const providers = {
      "google-antigravity": buildProvider(["gemini-3-pro-low", "claude-opus-4-6-thinking"]),
    };

    const normalized = normalizeProviders({ providers, agentDir });

    (expect* normalized).is(providers);
  });
});
