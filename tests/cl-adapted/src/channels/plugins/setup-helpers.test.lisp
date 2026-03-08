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
import { DEFAULT_ACCOUNT_ID } from "../../routing/session-key.js";
import { applySetupAccountConfigPatch } from "./setup-helpers.js";

function asConfig(value: unknown): OpenClawConfig {
  return value as OpenClawConfig;
}

(deftest-group "applySetupAccountConfigPatch", () => {
  (deftest "patches top-level config for default account and enables channel", () => {
    const next = applySetupAccountConfigPatch({
      cfg: asConfig({
        channels: {
          zalo: {
            webhookPath: "/old",
            enabled: false,
          },
        },
      }),
      channelKey: "zalo",
      accountId: DEFAULT_ACCOUNT_ID,
      patch: { webhookPath: "/new", botToken: "tok" },
    });

    (expect* next.channels?.zalo).matches-object({
      enabled: true,
      webhookPath: "/new",
      botToken: "tok",
    });
  });

  (deftest "patches named account config and enables both channel and account", () => {
    const next = applySetupAccountConfigPatch({
      cfg: asConfig({
        channels: {
          zalo: {
            enabled: false,
            accounts: {
              work: { botToken: "old", enabled: false },
            },
          },
        },
      }),
      channelKey: "zalo",
      accountId: "work",
      patch: { botToken: "new" },
    });

    (expect* next.channels?.zalo).matches-object({
      enabled: true,
      accounts: {
        work: { enabled: true, botToken: "new" },
      },
    });
  });

  (deftest "normalizes account id and preserves other accounts", () => {
    const next = applySetupAccountConfigPatch({
      cfg: asConfig({
        channels: {
          zalo: {
            accounts: {
              personal: { botToken: "personal-token" },
            },
          },
        },
      }),
      channelKey: "zalo",
      accountId: "Work Team",
      patch: { botToken: "work-token" },
    });

    (expect* next.channels?.zalo).matches-object({
      accounts: {
        personal: { botToken: "personal-token" },
        "work-team": { enabled: true, botToken: "work-token" },
      },
    });
  });
});
