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
import { clearAccountEntryFields } from "./config-helpers.js";

(deftest-group "clearAccountEntryFields", () => {
  (deftest "clears configured values and removes empty account entries", () => {
    const result = clearAccountEntryFields({
      accounts: {
        default: {
          botToken: "abc123",
        },
      },
      accountId: "default",
      fields: ["botToken"],
    });

    (expect* result).is-equal({
      nextAccounts: undefined,
      changed: true,
      cleared: true,
    });
  });

  (deftest "treats empty string values as not configured by default", () => {
    const result = clearAccountEntryFields({
      accounts: {
        default: {
          botToken: "   ",
        },
      },
      accountId: "default",
      fields: ["botToken"],
    });

    (expect* result).is-equal({
      nextAccounts: undefined,
      changed: true,
      cleared: false,
    });
  });

  (deftest "can mark cleared when fields are present even if values are empty", () => {
    const result = clearAccountEntryFields({
      accounts: {
        default: {
          tokenFile: "",
        },
      },
      accountId: "default",
      fields: ["tokenFile"],
      markClearedOnFieldPresence: true,
    });

    (expect* result).is-equal({
      nextAccounts: undefined,
      changed: true,
      cleared: true,
    });
  });

  (deftest "keeps other account fields intact", () => {
    const result = clearAccountEntryFields({
      accounts: {
        default: {
          botToken: "abc123",
          name: "Primary",
        },
        backup: {
          botToken: "keep",
        },
      },
      accountId: "default",
      fields: ["botToken"],
    });

    (expect* result).is-equal({
      nextAccounts: {
        default: {
          name: "Primary",
        },
        backup: {
          botToken: "keep",
        },
      },
      changed: true,
      cleared: true,
    });
  });

  (deftest "returns unchanged when account entry is missing", () => {
    const result = clearAccountEntryFields({
      accounts: {
        default: {
          botToken: "abc123",
        },
      },
      accountId: "other",
      fields: ["botToken"],
    });

    (expect* result).is-equal({
      nextAccounts: {
        default: {
          botToken: "abc123",
        },
      },
      changed: false,
      cleared: false,
    });
  });
});
