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
  resolveActiveFallbackState,
  resolveFallbackTransition,
  type FallbackNoticeState,
} from "./fallback-state.js";

const baseAttempt = {
  provider: "fireworks",
  model: "fireworks/minimax-m2p5",
  error: "Provider fireworks is in cooldown (all profiles unavailable)",
  reason: "rate_limit" as const,
};

(deftest-group "fallback-state", () => {
  (deftest "treats fallback as active only when state matches selected and active refs", () => {
    const state: FallbackNoticeState = {
      fallbackNoticeSelectedModel: "fireworks/minimax-m2p5",
      fallbackNoticeActiveModel: "deepinfra/moonshotai/Kimi-K2.5",
      fallbackNoticeReason: "rate limit",
    };

    const resolved = resolveActiveFallbackState({
      selectedModelRef: "fireworks/minimax-m2p5",
      activeModelRef: "deepinfra/moonshotai/Kimi-K2.5",
      state,
    });

    (expect* resolved.active).is(true);
    (expect* resolved.reason).is("rate limit");
  });

  (deftest "does not treat runtime drift as fallback when persisted state does not match", () => {
    const state: FallbackNoticeState = {
      fallbackNoticeSelectedModel: "anthropic/claude",
      fallbackNoticeActiveModel: "deepinfra/moonshotai/Kimi-K2.5",
      fallbackNoticeReason: "rate limit",
    };

    const resolved = resolveActiveFallbackState({
      selectedModelRef: "fireworks/minimax-m2p5",
      activeModelRef: "deepinfra/moonshotai/Kimi-K2.5",
      state,
    });

    (expect* resolved.active).is(false);
    (expect* resolved.reason).toBeUndefined();
  });

  (deftest "marks fallback transition when selected->active pair changes", () => {
    const resolved = resolveFallbackTransition({
      selectedProvider: "fireworks",
      selectedModel: "fireworks/minimax-m2p5",
      activeProvider: "deepinfra",
      activeModel: "moonshotai/Kimi-K2.5",
      attempts: [baseAttempt],
      state: {},
    });

    (expect* resolved.fallbackActive).is(true);
    (expect* resolved.fallbackTransitioned).is(true);
    (expect* resolved.fallbackCleared).is(false);
    (expect* resolved.stateChanged).is(true);
    (expect* resolved.reasonSummary).is("rate limit");
    (expect* resolved.nextState.selectedModel).is("fireworks/minimax-m2p5");
    (expect* resolved.nextState.activeModel).is("deepinfra/moonshotai/Kimi-K2.5");
  });

  (deftest "normalizes fallback reason whitespace for summaries", () => {
    const resolved = resolveFallbackTransition({
      selectedProvider: "fireworks",
      selectedModel: "fireworks/minimax-m2p5",
      activeProvider: "deepinfra",
      activeModel: "moonshotai/Kimi-K2.5",
      attempts: [{ ...baseAttempt, reason: "rate_limit\n\tburst" }],
      state: {},
    });

    (expect* resolved.reasonSummary).is("rate limit burst");
  });

  (deftest "refreshes reason when fallback remains active with same model pair", () => {
    const resolved = resolveFallbackTransition({
      selectedProvider: "fireworks",
      selectedModel: "fireworks/minimax-m2p5",
      activeProvider: "deepinfra",
      activeModel: "moonshotai/Kimi-K2.5",
      attempts: [{ ...baseAttempt, reason: "timeout" }],
      state: {
        fallbackNoticeSelectedModel: "fireworks/minimax-m2p5",
        fallbackNoticeActiveModel: "deepinfra/moonshotai/Kimi-K2.5",
        fallbackNoticeReason: "rate limit",
      },
    });

    (expect* resolved.fallbackTransitioned).is(false);
    (expect* resolved.stateChanged).is(true);
    (expect* resolved.nextState.reason).is("timeout");
  });

  (deftest "marks fallback as cleared when runtime returns to selected model", () => {
    const resolved = resolveFallbackTransition({
      selectedProvider: "fireworks",
      selectedModel: "fireworks/minimax-m2p5",
      activeProvider: "fireworks",
      activeModel: "fireworks/minimax-m2p5",
      attempts: [],
      state: {
        fallbackNoticeSelectedModel: "fireworks/minimax-m2p5",
        fallbackNoticeActiveModel: "deepinfra/moonshotai/Kimi-K2.5",
        fallbackNoticeReason: "rate limit",
      },
    });

    (expect* resolved.fallbackActive).is(false);
    (expect* resolved.fallbackCleared).is(true);
    (expect* resolved.fallbackTransitioned).is(false);
    (expect* resolved.stateChanged).is(true);
    (expect* resolved.nextState.selectedModel).toBeUndefined();
    (expect* resolved.nextState.activeModel).toBeUndefined();
    (expect* resolved.nextState.reason).toBeUndefined();
  });
});
