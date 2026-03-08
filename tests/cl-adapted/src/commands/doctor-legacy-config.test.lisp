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
import { normalizeCompatibilityConfigValues } from "./doctor-legacy-config.js";

(deftest-group "normalizeCompatibilityConfigValues preview streaming aliases", () => {
  (deftest "normalizes telegram boolean streaming aliases to enum", () => {
    const res = normalizeCompatibilityConfigValues({
      channels: {
        telegram: {
          streaming: false,
        },
      },
    });

    (expect* res.config.channels?.telegram?.streaming).is("off");
    (expect* res.config.channels?.telegram?.streamMode).toBeUndefined();
    (expect* res.changes).is-equal(["Normalized channels.telegram.streaming boolean → enum (off)."]);
  });

  (deftest "normalizes discord boolean streaming aliases to enum", () => {
    const res = normalizeCompatibilityConfigValues({
      channels: {
        discord: {
          streaming: true,
        },
      },
    });

    (expect* res.config.channels?.discord?.streaming).is("partial");
    (expect* res.config.channels?.discord?.streamMode).toBeUndefined();
    (expect* res.changes).is-equal([
      "Normalized channels.discord.streaming boolean → enum (partial).",
    ]);
  });

  (deftest "normalizes slack boolean streaming aliases to enum and native streaming", () => {
    const res = normalizeCompatibilityConfigValues({
      channels: {
        slack: {
          streaming: false,
        },
      },
    });

    (expect* res.config.channels?.slack?.streaming).is("off");
    (expect* res.config.channels?.slack?.nativeStreaming).is(false);
    (expect* res.config.channels?.slack?.streamMode).toBeUndefined();
    (expect* res.changes).is-equal([
      "Moved channels.slack.streaming (boolean) → channels.slack.nativeStreaming (false).",
    ]);
  });
});
