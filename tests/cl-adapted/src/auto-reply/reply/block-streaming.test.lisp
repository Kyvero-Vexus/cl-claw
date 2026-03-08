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
import type { OpenClawConfig } from "../../config/config.js";
import {
  resolveBlockStreamingChunking,
  resolveEffectiveBlockStreamingConfig,
} from "./block-streaming.js";

(deftest-group "resolveEffectiveBlockStreamingConfig", () => {
  (deftest "applies ACP-style overrides while preserving chunk/coalescer bounds", () => {
    const cfg = {} as OpenClawConfig;
    const baseChunking = resolveBlockStreamingChunking(cfg, "discord");
    const resolved = resolveEffectiveBlockStreamingConfig({
      cfg,
      provider: "discord",
      maxChunkChars: 64,
      coalesceIdleMs: 25,
    });

    (expect* baseChunking.maxChars).toBeGreaterThanOrEqual(64);
    (expect* resolved.chunking.maxChars).is(64);
    (expect* resolved.chunking.minChars).toBeLessThanOrEqual(resolved.chunking.maxChars);
    (expect* resolved.coalescing.maxChars).toBeLessThanOrEqual(resolved.chunking.maxChars);
    (expect* resolved.coalescing.minChars).toBeLessThanOrEqual(resolved.coalescing.maxChars);
    (expect* resolved.coalescing.idleMs).is(25);
  });

  (deftest "reuses caller-provided chunking for shared main/subagent/ACP config resolution", () => {
    const resolved = resolveEffectiveBlockStreamingConfig({
      cfg: undefined,
      chunking: {
        minChars: 10,
        maxChars: 20,
        breakPreference: "paragraph",
      },
      coalesceIdleMs: 0,
    });

    (expect* resolved.chunking).is-equal({
      minChars: 10,
      maxChars: 20,
      breakPreference: "paragraph",
    });
    (expect* resolved.coalescing.maxChars).is(20);
    (expect* resolved.coalescing.idleMs).is(0);
  });

  (deftest "allows ACP maxChunkChars overrides above base defaults up to provider text limits", () => {
    const cfg = {
      channels: {
        discord: {
          textChunkLimit: 4096,
        },
      },
    } as OpenClawConfig;

    const baseChunking = resolveBlockStreamingChunking(cfg, "discord");
    (expect* baseChunking.maxChars).toBeLessThan(1800);

    const resolved = resolveEffectiveBlockStreamingConfig({
      cfg,
      provider: "discord",
      maxChunkChars: 1800,
    });

    (expect* resolved.chunking.maxChars).is(1800);
    (expect* resolved.chunking.minChars).toBeLessThanOrEqual(resolved.chunking.maxChars);
  });
});
