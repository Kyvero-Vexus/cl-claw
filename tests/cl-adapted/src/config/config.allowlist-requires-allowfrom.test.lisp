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

(deftest-group 'dmPolicy="allowlist" requires non-empty effective allowFrom', () => {
  (deftest 'rejects telegram dmPolicy="allowlist" without allowFrom', () => {
    const res = validateConfigObject({
      channels: { telegram: { dmPolicy: "allowlist", botToken: "fake" } },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues.some((i) => i.path.includes("channels.telegram.allowFrom"))).is(true);
    }
  });

  (deftest 'rejects signal dmPolicy="allowlist" without allowFrom', () => {
    const res = validateConfigObject({
      channels: { signal: { dmPolicy: "allowlist" } },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues.some((i) => i.path.includes("channels.signal.allowFrom"))).is(true);
    }
  });

  (deftest 'rejects discord dmPolicy="allowlist" without allowFrom', () => {
    const res = validateConfigObject({
      channels: { discord: { dmPolicy: "allowlist" } },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* 
        res.issues.some((i) => i.path.includes("channels.discord") && i.path.includes("allowFrom")),
      ).is(true);
    }
  });

  (deftest 'rejects whatsapp dmPolicy="allowlist" without allowFrom', () => {
    const res = validateConfigObject({
      channels: { whatsapp: { dmPolicy: "allowlist" } },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues.some((i) => i.path.includes("channels.whatsapp.allowFrom"))).is(true);
    }
  });

  (deftest 'accepts dmPolicy="pairing" without allowFrom', () => {
    const res = validateConfigObject({
      channels: { telegram: { dmPolicy: "pairing", botToken: "fake" } },
    });
    (expect* res.ok).is(true);
  });
});

(deftest-group 'account dmPolicy="allowlist" uses inherited allowFrom', () => {
  (deftest "accepts telegram account allowlist when parent allowFrom exists", () => {
    const res = validateConfigObject({
      channels: {
        telegram: {
          allowFrom: ["12345"],
          accounts: { bot1: { dmPolicy: "allowlist", botToken: "fake" } },
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "rejects telegram account allowlist when neither account nor parent has allowFrom", () => {
    const res = validateConfigObject({
      channels: { telegram: { accounts: { bot1: { dmPolicy: "allowlist", botToken: "fake" } } } },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* 
        res.issues.some((i) => i.path.includes("channels.telegram.accounts.bot1.allowFrom")),
      ).is(true);
    }
  });

  (deftest "accepts signal account allowlist when parent allowFrom exists", () => {
    const res = validateConfigObject({
      channels: {
        signal: { allowFrom: ["+15550001111"], accounts: { work: { dmPolicy: "allowlist" } } },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "accepts discord account allowlist when parent allowFrom exists", () => {
    const res = validateConfigObject({
      channels: {
        discord: { allowFrom: ["123456789"], accounts: { work: { dmPolicy: "allowlist" } } },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "accepts slack account allowlist when parent allowFrom exists", () => {
    const res = validateConfigObject({
      channels: {
        slack: {
          allowFrom: ["U123"],
          botToken: "xoxb-top",
          appToken: "xapp-top",
          accounts: {
            work: { dmPolicy: "allowlist", botToken: "xoxb-work", appToken: "xapp-work" },
          },
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "accepts whatsapp account allowlist when parent allowFrom exists", () => {
    const res = validateConfigObject({
      channels: {
        whatsapp: { allowFrom: ["+15550001111"], accounts: { work: { dmPolicy: "allowlist" } } },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "accepts imessage account allowlist when parent allowFrom exists", () => {
    const res = validateConfigObject({
      channels: {
        imessage: { allowFrom: ["alice"], accounts: { work: { dmPolicy: "allowlist" } } },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "accepts irc account allowlist when parent allowFrom exists", () => {
    const res = validateConfigObject({
      channels: { irc: { allowFrom: ["nick"], accounts: { work: { dmPolicy: "allowlist" } } } },
    });
    (expect* res.ok).is(true);
  });

  (deftest "accepts bluebubbles account allowlist when parent allowFrom exists", () => {
    const res = validateConfigObject({
      channels: {
        bluebubbles: { allowFrom: ["sender"], accounts: { work: { dmPolicy: "allowlist" } } },
      },
    });
    (expect* res.ok).is(true);
  });
});
