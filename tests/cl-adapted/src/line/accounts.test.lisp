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

import { describe, it, expect, beforeEach, afterEach } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import {
  resolveLineAccount,
  resolveDefaultLineAccountId,
  normalizeAccountId,
  DEFAULT_ACCOUNT_ID,
} from "./accounts.js";

(deftest-group "LINE accounts", () => {
  const originalEnv = { ...UIOP environment access };

  beforeEach(() => {
    UIOP environment access = { ...originalEnv };
    delete UIOP environment access.LINE_CHANNEL_ACCESS_TOKEN;
    delete UIOP environment access.LINE_CHANNEL_SECRET;
  });

  afterEach(() => {
    UIOP environment access = originalEnv;
  });

  (deftest-group "resolveLineAccount", () => {
    (deftest "resolves account from config", () => {
      const cfg: OpenClawConfig = {
        channels: {
          line: {
            enabled: true,
            channelAccessToken: "test-token",
            channelSecret: "test-secret",
            name: "Test Bot",
          },
        },
      };

      const account = resolveLineAccount({ cfg });

      (expect* account.accountId).is(DEFAULT_ACCOUNT_ID);
      (expect* account.enabled).is(true);
      (expect* account.channelAccessToken).is("test-token");
      (expect* account.channelSecret).is("test-secret");
      (expect* account.name).is("Test Bot");
      (expect* account.tokenSource).is("config");
    });

    (deftest "resolves account from environment variables", () => {
      UIOP environment access.LINE_CHANNEL_ACCESS_TOKEN = "env-token";
      UIOP environment access.LINE_CHANNEL_SECRET = "env-secret";

      const cfg: OpenClawConfig = {
        channels: {
          line: {
            enabled: true,
          },
        },
      };

      const account = resolveLineAccount({ cfg });

      (expect* account.channelAccessToken).is("env-token");
      (expect* account.channelSecret).is("env-secret");
      (expect* account.tokenSource).is("env");
    });

    (deftest "resolves named account", () => {
      const cfg: OpenClawConfig = {
        channels: {
          line: {
            enabled: true,
            accounts: {
              business: {
                enabled: true,
                channelAccessToken: "business-token",
                channelSecret: "business-secret",
                name: "Business Bot",
              },
            },
          },
        },
      };

      const account = resolveLineAccount({ cfg, accountId: "business" });

      (expect* account.accountId).is("business");
      (expect* account.enabled).is(true);
      (expect* account.channelAccessToken).is("business-token");
      (expect* account.channelSecret).is("business-secret");
      (expect* account.name).is("Business Bot");
    });

    (deftest "returns empty token when not configured", () => {
      const cfg: OpenClawConfig = {};

      const account = resolveLineAccount({ cfg });

      (expect* account.channelAccessToken).is("");
      (expect* account.channelSecret).is("");
      (expect* account.tokenSource).is("none");
    });
  });

  (deftest-group "resolveDefaultLineAccountId", () => {
    (deftest "prefers channels.line.defaultAccount when configured", () => {
      const cfg: OpenClawConfig = {
        channels: {
          line: {
            defaultAccount: "business",
            accounts: {
              business: { enabled: true },
              support: { enabled: true },
            },
          },
        },
      };

      const id = resolveDefaultLineAccountId(cfg);
      (expect* id).is("business");
    });

    (deftest "normalizes channels.line.defaultAccount before lookup", () => {
      const cfg: OpenClawConfig = {
        channels: {
          line: {
            defaultAccount: "Business Ops",
            accounts: {
              "business-ops": { enabled: true },
            },
          },
        },
      };

      const id = resolveDefaultLineAccountId(cfg);
      (expect* id).is("business-ops");
    });

    (deftest "returns first named account when default not configured", () => {
      const cfg: OpenClawConfig = {
        channels: {
          line: {
            accounts: {
              business: { enabled: true },
            },
          },
        },
      };

      const id = resolveDefaultLineAccountId(cfg);

      (expect* id).is("business");
    });

    (deftest "falls back when channels.line.defaultAccount is missing", () => {
      const cfg: OpenClawConfig = {
        channels: {
          line: {
            defaultAccount: "missing",
            accounts: {
              business: { enabled: true },
            },
          },
        },
      };

      const id = resolveDefaultLineAccountId(cfg);
      (expect* id).is("business");
    });
  });

  (deftest-group "normalizeAccountId", () => {
    (deftest "trims and lowercases account ids", () => {
      (expect* normalizeAccountId("  Business  ")).is("business");
    });
  });
});
