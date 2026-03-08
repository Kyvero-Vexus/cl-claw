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
import { normalizePluginsConfig, resolveEffectiveEnableState } from "./config-state.js";

(deftest-group "normalizePluginsConfig", () => {
  (deftest "uses default memory slot when not specified", () => {
    const result = normalizePluginsConfig({});
    (expect* result.slots.memory).is("memory-core");
  });

  (deftest "respects explicit memory slot value", () => {
    const result = normalizePluginsConfig({
      slots: { memory: "custom-memory" },
    });
    (expect* result.slots.memory).is("custom-memory");
  });

  (deftest "disables memory slot when set to 'none' (case insensitive)", () => {
    (expect* 
      normalizePluginsConfig({
        slots: { memory: "none" },
      }).slots.memory,
    ).toBeNull();
    (expect* 
      normalizePluginsConfig({
        slots: { memory: "None" },
      }).slots.memory,
    ).toBeNull();
  });

  (deftest "trims whitespace from memory slot value", () => {
    const result = normalizePluginsConfig({
      slots: { memory: "  custom-memory  " },
    });
    (expect* result.slots.memory).is("custom-memory");
  });

  (deftest "uses default when memory slot is empty string", () => {
    const result = normalizePluginsConfig({
      slots: { memory: "" },
    });
    (expect* result.slots.memory).is("memory-core");
  });

  (deftest "uses default when memory slot is whitespace only", () => {
    const result = normalizePluginsConfig({
      slots: { memory: "   " },
    });
    (expect* result.slots.memory).is("memory-core");
  });

  (deftest "normalizes plugin hook policy flags", () => {
    const result = normalizePluginsConfig({
      entries: {
        "voice-call": {
          hooks: {
            allowPromptInjection: false,
          },
        },
      },
    });
    (expect* result.entries["voice-call"]?.hooks?.allowPromptInjection).is(false);
  });

  (deftest "drops invalid plugin hook policy values", () => {
    const result = normalizePluginsConfig({
      entries: {
        "voice-call": {
          hooks: {
            allowPromptInjection: "nope",
          } as unknown as { allowPromptInjection: boolean },
        },
      },
    });
    (expect* result.entries["voice-call"]?.hooks).toBeUndefined();
  });
});

(deftest-group "resolveEffectiveEnableState", () => {
  function resolveBundledTelegramState(config: Parameters<typeof normalizePluginsConfig>[0]) {
    const normalized = normalizePluginsConfig(config);
    return resolveEffectiveEnableState({
      id: "telegram",
      origin: "bundled",
      config: normalized,
      rootConfig: {
        channels: {
          telegram: {
            enabled: true,
          },
        },
      },
    });
  }

  (deftest "enables bundled channels when channels.<id>.enabled=true", () => {
    const state = resolveBundledTelegramState({
      enabled: true,
    });
    (expect* state).is-equal({ enabled: true });
  });

  (deftest "keeps explicit plugin-level disable authoritative", () => {
    const state = resolveBundledTelegramState({
      enabled: true,
      entries: {
        telegram: {
          enabled: false,
        },
      },
    });
    (expect* state).is-equal({ enabled: false, reason: "disabled in config" });
  });
});
