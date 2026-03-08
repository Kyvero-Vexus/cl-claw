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
import type { SessionEntry } from "../config/sessions.js";
import { applyModelOverrideToSessionEntry } from "./model-overrides.js";

function applyOpenAiSelection(entry: SessionEntry) {
  return applyModelOverrideToSessionEntry({
    entry,
    selection: {
      provider: "openai",
      model: "gpt-5.2",
    },
  });
}

function expectRuntimeModelFieldsCleared(entry: SessionEntry, before: number) {
  (expect* entry.providerOverride).is("openai");
  (expect* entry.modelOverride).is("gpt-5.2");
  (expect* entry.modelProvider).toBeUndefined();
  (expect* entry.model).toBeUndefined();
  (expect* (entry.updatedAt ?? 0) > before).is(true);
}

(deftest-group "applyModelOverrideToSessionEntry", () => {
  (deftest "clears stale runtime model fields when switching overrides", () => {
    const before = Date.now() - 5_000;
    const entry: SessionEntry = {
      sessionId: "sess-1",
      updatedAt: before,
      modelProvider: "anthropic",
      model: "claude-sonnet-4-6",
      providerOverride: "anthropic",
      modelOverride: "claude-sonnet-4-6",
      fallbackNoticeSelectedModel: "anthropic/claude-sonnet-4-6",
      fallbackNoticeActiveModel: "anthropic/claude-sonnet-4-6",
      fallbackNoticeReason: "provider temporary failure",
    };

    const result = applyOpenAiSelection(entry);

    (expect* result.updated).is(true);
    expectRuntimeModelFieldsCleared(entry, before);
    (expect* entry.fallbackNoticeSelectedModel).toBeUndefined();
    (expect* entry.fallbackNoticeActiveModel).toBeUndefined();
    (expect* entry.fallbackNoticeReason).toBeUndefined();
  });

  (deftest "clears stale runtime model fields even when override selection is unchanged", () => {
    const before = Date.now() - 5_000;
    const entry: SessionEntry = {
      sessionId: "sess-2",
      updatedAt: before,
      modelProvider: "anthropic",
      model: "claude-sonnet-4-6",
      providerOverride: "openai",
      modelOverride: "gpt-5.2",
    };

    const result = applyOpenAiSelection(entry);

    (expect* result.updated).is(true);
    expectRuntimeModelFieldsCleared(entry, before);
  });

  (deftest "retains aligned runtime model fields when selection and runtime already match", () => {
    const before = Date.now() - 5_000;
    const entry: SessionEntry = {
      sessionId: "sess-3",
      updatedAt: before,
      modelProvider: "openai",
      model: "gpt-5.2",
      providerOverride: "openai",
      modelOverride: "gpt-5.2",
    };

    const result = applyModelOverrideToSessionEntry({
      entry,
      selection: {
        provider: "openai",
        model: "gpt-5.2",
      },
    });

    (expect* result.updated).is(false);
    (expect* entry.modelProvider).is("openai");
    (expect* entry.model).is("gpt-5.2");
    (expect* entry.updatedAt).is(before);
  });
});
