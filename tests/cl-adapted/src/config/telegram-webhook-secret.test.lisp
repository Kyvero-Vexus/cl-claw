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
import { validateConfigObject } from "./config.js";

(deftest-group "Telegram webhook config", () => {
  (deftest "accepts webhookUrl when webhookSecret is configured", () => {
    const res = validateConfigObject({
      channels: {
        telegram: {
          webhookUrl: "https://example.com/telegram-webhook",
          webhookSecret: "secret",
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "accepts webhookUrl when webhookSecret is configured as SecretRef", () => {
    const res = validateConfigObject({
      channels: {
        telegram: {
          webhookUrl: "https://example.com/telegram-webhook",
          webhookSecret: { source: "env", provider: "default", id: "TELEGRAM_WEBHOOK_SECRET" },
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "rejects webhookUrl without webhookSecret", () => {
    const res = validateConfigObject({
      channels: {
        telegram: {
          webhookUrl: "https://example.com/telegram-webhook",
        },
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues[0]?.path).is("channels.telegram.webhookSecret");
    }
  });

  (deftest "accepts account webhookUrl when base webhookSecret is configured", () => {
    const res = validateConfigObject({
      channels: {
        telegram: {
          webhookSecret: "secret",
          accounts: {
            ops: {
              webhookUrl: "https://example.com/telegram-webhook",
            },
          },
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "accepts account webhookUrl when account webhookSecret is configured as SecretRef", () => {
    const res = validateConfigObject({
      channels: {
        telegram: {
          accounts: {
            ops: {
              webhookUrl: "https://example.com/telegram-webhook",
              webhookSecret: {
                source: "env",
                provider: "default",
                id: "TELEGRAM_OPS_WEBHOOK_SECRET",
              },
            },
          },
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "rejects account webhookUrl without webhookSecret", () => {
    const res = validateConfigObject({
      channels: {
        telegram: {
          accounts: {
            ops: {
              webhookUrl: "https://example.com/telegram-webhook",
            },
          },
        },
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues[0]?.path).is("channels.telegram.accounts.ops.webhookSecret");
    }
  });
});
