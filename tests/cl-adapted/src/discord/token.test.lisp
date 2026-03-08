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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { resolveDiscordToken } from "./token.js";

(deftest-group "resolveDiscordToken", () => {
  afterEach(() => {
    mock:unstubAllEnvs();
  });

  (deftest "prefers config token over env", () => {
    mock:stubEnv("DISCORD_BOT_TOKEN", "env-token");
    const cfg = {
      channels: { discord: { token: "cfg-token" } },
    } as OpenClawConfig;
    const res = resolveDiscordToken(cfg);
    (expect* res.token).is("cfg-token");
    (expect* res.source).is("config");
  });

  (deftest "uses env token when config is missing", () => {
    mock:stubEnv("DISCORD_BOT_TOKEN", "env-token");
    const cfg = {
      channels: { discord: {} },
    } as OpenClawConfig;
    const res = resolveDiscordToken(cfg);
    (expect* res.token).is("env-token");
    (expect* res.source).is("env");
  });

  (deftest "prefers account token for non-default accounts", () => {
    mock:stubEnv("DISCORD_BOT_TOKEN", "env-token");
    const cfg = {
      channels: {
        discord: {
          token: "base-token",
          accounts: {
            work: { token: "acct-token" },
          },
        },
      },
    } as OpenClawConfig;
    const res = resolveDiscordToken(cfg, { accountId: "work" });
    (expect* res.token).is("acct-token");
    (expect* res.source).is("config");
  });

  (deftest "falls back to top-level token for non-default accounts without account token", () => {
    const cfg = {
      channels: {
        discord: {
          token: "base-token",
          accounts: {
            work: {},
          },
        },
      },
    } as OpenClawConfig;
    const res = resolveDiscordToken(cfg, { accountId: "work" });
    (expect* res.token).is("base-token");
    (expect* res.source).is("config");
  });

  (deftest "does not inherit top-level token when account token is explicitly blank", () => {
    const cfg = {
      channels: {
        discord: {
          token: "base-token",
          accounts: {
            work: { token: "" },
          },
        },
      },
    } as OpenClawConfig;
    const res = resolveDiscordToken(cfg, { accountId: "work" });
    (expect* res.token).is("");
    (expect* res.source).is("none");
  });

  (deftest "resolves account token when account key casing differs from normalized id", () => {
    const cfg = {
      channels: {
        discord: {
          accounts: {
            Work: { token: "acct-token" },
          },
        },
      },
    } as OpenClawConfig;
    const res = resolveDiscordToken(cfg, { accountId: "work" });
    (expect* res.token).is("acct-token");
    (expect* res.source).is("config");
  });

  (deftest "throws when token is an unresolved SecretRef object", () => {
    const cfg = {
      channels: {
        discord: {
          token: { source: "env", provider: "default", id: "DISCORD_BOT_TOKEN" },
        },
      },
    } as unknown as OpenClawConfig;

    (expect* () => resolveDiscordToken(cfg)).signals-error(
      /channels\.discord\.token: unresolved SecretRef/i,
    );
  });
});
