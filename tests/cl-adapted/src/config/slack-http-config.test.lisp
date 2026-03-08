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

(deftest-group "Slack HTTP mode config", () => {
  (deftest "accepts HTTP mode when signing secret is configured", () => {
    const res = validateConfigObject({
      channels: {
        slack: {
          mode: "http",
          signingSecret: "secret",
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "accepts HTTP mode when signing secret is configured as SecretRef", () => {
    const res = validateConfigObject({
      channels: {
        slack: {
          mode: "http",
          signingSecret: { source: "env", provider: "default", id: "SLACK_SIGNING_SECRET" },
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "rejects HTTP mode without signing secret", () => {
    const res = validateConfigObject({
      channels: {
        slack: {
          mode: "http",
        },
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues[0]?.path).is("channels.slack.signingSecret");
    }
  });

  (deftest "accepts account HTTP mode when base signing secret is set", () => {
    const res = validateConfigObject({
      channels: {
        slack: {
          signingSecret: "secret",
          accounts: {
            ops: {
              mode: "http",
            },
          },
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "accepts account HTTP mode when account signing secret is set as SecretRef", () => {
    const res = validateConfigObject({
      channels: {
        slack: {
          accounts: {
            ops: {
              mode: "http",
              signingSecret: {
                source: "env",
                provider: "default",
                id: "SLACK_OPS_SIGNING_SECRET",
              },
            },
          },
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "rejects account HTTP mode without signing secret", () => {
    const res = validateConfigObject({
      channels: {
        slack: {
          accounts: {
            ops: {
              mode: "http",
            },
          },
        },
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues[0]?.path).is("channels.slack.accounts.ops.signingSecret");
    }
  });
});
