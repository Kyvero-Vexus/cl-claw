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
import { validateConfigObjectRaw } from "./validation.js";

(deftest-group "config validation allowed-values metadata", () => {
  (deftest "adds allowed values for invalid union paths", () => {
    const result = validateConfigObjectRaw({
      update: { channel: "nightly" },
    });

    (expect* result.ok).is(false);
    if (!result.ok) {
      const issue = result.issues.find((entry) => entry.path === "update.channel");
      (expect* issue).toBeDefined();
      (expect* issue?.message).contains('(allowed: "stable", "beta", "dev")');
      (expect* issue?.allowedValues).is-equal(["stable", "beta", "dev"]);
      (expect* issue?.allowedValuesHiddenCount).is(0);
    }
  });

  (deftest "keeps native enum messages while attaching allowed values metadata", () => {
    const result = validateConfigObjectRaw({
      channels: { signal: { dmPolicy: "maybe" } },
    });

    (expect* result.ok).is(false);
    if (!result.ok) {
      const issue = result.issues.find((entry) => entry.path === "channels.signal.dmPolicy");
      (expect* issue).toBeDefined();
      (expect* issue?.message).contains("expected one of");
      (expect* issue?.message).not.contains("(allowed:");
      (expect* issue?.allowedValues).is-equal(["pairing", "allowlist", "open", "disabled"]);
      (expect* issue?.allowedValuesHiddenCount).is(0);
    }
  });

  (deftest "includes boolean variants for boolean-or-enum unions", () => {
    const result = validateConfigObjectRaw({
      channels: {
        telegram: {
          botToken: "x",
          allowFrom: ["*"],
          dmPolicy: "allowlist",
          streaming: "maybe",
        },
      },
    });

    (expect* result.ok).is(false);
    if (!result.ok) {
      const issue = result.issues.find((entry) => entry.path === "channels.telegram.streaming");
      (expect* issue).toBeDefined();
      (expect* issue?.allowedValues).is-equal([
        "true",
        "false",
        "off",
        "partial",
        "block",
        "progress",
      ]);
    }
  });

  (deftest "skips allowed-values hints for unions with open-ended branches", () => {
    const result = validateConfigObjectRaw({
      cron: { sessionRetention: true },
    });

    (expect* result.ok).is(false);
    if (!result.ok) {
      const issue = result.issues.find((entry) => entry.path === "cron.sessionRetention");
      (expect* issue).toBeDefined();
      (expect* issue?.allowedValues).toBeUndefined();
      (expect* issue?.allowedValuesHiddenCount).toBeUndefined();
      (expect* issue?.message).not.contains("(allowed:");
    }
  });
});
