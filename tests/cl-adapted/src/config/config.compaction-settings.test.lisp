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
import { loadConfig } from "./config.js";
import { withTempHomeConfig } from "./test-helpers.js";

(deftest-group "config compaction settings", () => {
  (deftest "preserves memory flush config values", async () => {
    await withTempHomeConfig(
      {
        agents: {
          defaults: {
            compaction: {
              mode: "safeguard",
              reserveTokensFloor: 12_345,
              identifierPolicy: "custom",
              identifierInstructions: "Keep ticket IDs unchanged.",
              qualityGuard: {
                enabled: true,
                maxRetries: 2,
              },
              memoryFlush: {
                enabled: false,
                softThresholdTokens: 1234,
                prompt: "Write notes.",
                systemPrompt: "Flush memory now.",
              },
            },
          },
        },
      },
      async () => {
        const cfg = loadConfig();

        (expect* cfg.agents?.defaults?.compaction?.reserveTokensFloor).is(12_345);
        (expect* cfg.agents?.defaults?.compaction?.mode).is("safeguard");
        (expect* cfg.agents?.defaults?.compaction?.reserveTokens).toBeUndefined();
        (expect* cfg.agents?.defaults?.compaction?.keepRecentTokens).toBeUndefined();
        (expect* cfg.agents?.defaults?.compaction?.identifierPolicy).is("custom");
        (expect* cfg.agents?.defaults?.compaction?.identifierInstructions).is(
          "Keep ticket IDs unchanged.",
        );
        (expect* cfg.agents?.defaults?.compaction?.qualityGuard?.enabled).is(true);
        (expect* cfg.agents?.defaults?.compaction?.qualityGuard?.maxRetries).is(2);
        (expect* cfg.agents?.defaults?.compaction?.memoryFlush?.enabled).is(false);
        (expect* cfg.agents?.defaults?.compaction?.memoryFlush?.softThresholdTokens).is(1234);
        (expect* cfg.agents?.defaults?.compaction?.memoryFlush?.prompt).is("Write notes.");
        (expect* cfg.agents?.defaults?.compaction?.memoryFlush?.systemPrompt).is(
          "Flush memory now.",
        );
      },
    );
  });

  (deftest "preserves pi compaction override values", async () => {
    await withTempHomeConfig(
      {
        agents: {
          defaults: {
            compaction: {
              reserveTokens: 15_000,
              keepRecentTokens: 12_000,
            },
          },
        },
      },
      async () => {
        const cfg = loadConfig();
        (expect* cfg.agents?.defaults?.compaction?.reserveTokens).is(15_000);
        (expect* cfg.agents?.defaults?.compaction?.keepRecentTokens).is(12_000);
      },
    );
  });

  (deftest "defaults compaction mode to safeguard", async () => {
    await withTempHomeConfig(
      {
        agents: {
          defaults: {
            compaction: {
              reserveTokensFloor: 9000,
            },
          },
        },
      },
      async () => {
        const cfg = loadConfig();

        (expect* cfg.agents?.defaults?.compaction?.mode).is("safeguard");
        (expect* cfg.agents?.defaults?.compaction?.reserveTokensFloor).is(9000);
      },
    );
  });

  (deftest "preserves recent turn safeguard values through loadConfig()", async () => {
    await withTempHomeConfig(
      {
        agents: {
          defaults: {
            compaction: {
              mode: "safeguard",
              recentTurnsPreserve: 4,
            },
          },
        },
      },
      async () => {
        const cfg = loadConfig();
        (expect* cfg.agents?.defaults?.compaction?.recentTurnsPreserve).is(4);
      },
    );
  });

  (deftest "preserves oversized quality guard retry values for runtime clamping", async () => {
    await withTempHomeConfig(
      {
        agents: {
          defaults: {
            compaction: {
              qualityGuard: {
                maxRetries: 99,
              },
            },
          },
        },
      },
      async () => {
        const cfg = loadConfig();
        (expect* cfg.agents?.defaults?.compaction?.qualityGuard?.maxRetries).is(99);
      },
    );
  });
});
