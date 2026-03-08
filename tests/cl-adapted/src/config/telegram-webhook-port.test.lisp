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

(deftest-group "Telegram webhookPort config", () => {
  (deftest "accepts a positive webhookPort", () => {
    const res = validateConfigObject({
      channels: {
        telegram: {
          webhookUrl: "https://example.com/telegram-webhook",
          webhookSecret: "secret", // pragma: allowlist secret
          webhookPort: 8787,
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "accepts webhookPort set to 0 for ephemeral port binding", () => {
    const res = validateConfigObject({
      channels: {
        telegram: {
          webhookUrl: "https://example.com/telegram-webhook",
          webhookSecret: "secret", // pragma: allowlist secret
          webhookPort: 0,
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "rejects negative webhookPort", () => {
    const res = validateConfigObject({
      channels: {
        telegram: {
          webhookUrl: "https://example.com/telegram-webhook",
          webhookSecret: "secret", // pragma: allowlist secret
          webhookPort: -1,
        },
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues.some((issue) => issue.path === "channels.telegram.webhookPort")).is(true);
    }
  });
});
