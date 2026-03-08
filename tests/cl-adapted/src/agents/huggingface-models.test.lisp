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
  discoverHuggingfaceModels,
  HUGGINGFACE_MODEL_CATALOG,
  buildHuggingfaceModelDefinition,
  isHuggingfacePolicyLocked,
} from "./huggingface-models.js";

(deftest-group "huggingface-models", () => {
  (deftest "buildHuggingfaceModelDefinition returns config with required fields", () => {
    const entry = HUGGINGFACE_MODEL_CATALOG[0];
    const def = buildHuggingfaceModelDefinition(entry);
    (expect* def.id).is(entry.id);
    (expect* def.name).is(entry.name);
    (expect* def.reasoning).is(entry.reasoning);
    (expect* def.input).is-equal(entry.input);
    (expect* def.cost).is-equal(entry.cost);
    (expect* def.contextWindow).is(entry.contextWindow);
    (expect* def.maxTokens).is(entry.maxTokens);
  });

  (deftest "discoverHuggingfaceModels returns static catalog when apiKey is empty", async () => {
    const models = await discoverHuggingfaceModels("");
    (expect* models).has-length(HUGGINGFACE_MODEL_CATALOG.length);
    (expect* models.map((m) => m.id)).is-equal(HUGGINGFACE_MODEL_CATALOG.map((m) => m.id));
  });

  (deftest "discoverHuggingfaceModels returns static catalog in test env (VITEST)", async () => {
    const models = await discoverHuggingfaceModels("hf_test_token");
    (expect* models).has-length(HUGGINGFACE_MODEL_CATALOG.length);
    (expect* models[0].id).is("deepseek-ai/DeepSeek-R1");
  });

  (deftest-group "isHuggingfacePolicyLocked", () => {
    (deftest "returns true for :cheapest and :fastest refs", () => {
      (expect* isHuggingfacePolicyLocked("huggingface/deepseek-ai/DeepSeek-R1:cheapest")).is(true);
      (expect* isHuggingfacePolicyLocked("huggingface/deepseek-ai/DeepSeek-R1:fastest")).is(true);
    });
    (deftest "returns false for base ref and :provider refs", () => {
      (expect* isHuggingfacePolicyLocked("huggingface/deepseek-ai/DeepSeek-R1")).is(false);
      (expect* isHuggingfacePolicyLocked("huggingface/foo:together")).is(false);
    });
  });
});
