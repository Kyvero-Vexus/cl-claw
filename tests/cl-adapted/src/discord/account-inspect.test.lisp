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
import type { OpenClawConfig } from "../config/config.js";
import { inspectDiscordAccount } from "./account-inspect.js";

function asConfig(value: unknown): OpenClawConfig {
  return value as OpenClawConfig;
}

(deftest-group "inspectDiscordAccount", () => {
  (deftest "prefers account token over channel token and strips Bot prefix", () => {
    const inspected = inspectDiscordAccount({
      cfg: asConfig({
        channels: {
          discord: {
            token: "Bot channel-token",
            accounts: {
              work: {
                token: "Bot account-token",
              },
            },
          },
        },
      }),
      accountId: "work",
    });

    (expect* inspected.token).is("account-token");
    (expect* inspected.tokenSource).is("config");
    (expect* inspected.tokenStatus).is("available");
    (expect* inspected.configured).is(true);
  });

  (deftest "reports configured_unavailable for unresolved configured secret input", () => {
    const inspected = inspectDiscordAccount({
      cfg: asConfig({
        channels: {
          discord: {
            accounts: {
              work: {
                token: { source: "env", id: "DISCORD_TOKEN" },
              },
            },
          },
        },
      }),
      accountId: "work",
    });

    (expect* inspected.token).is("");
    (expect* inspected.tokenSource).is("config");
    (expect* inspected.tokenStatus).is("configured_unavailable");
    (expect* inspected.configured).is(true);
  });

  (deftest "does not fall back when account token key exists but is missing", () => {
    const inspected = inspectDiscordAccount({
      cfg: asConfig({
        channels: {
          discord: {
            token: "Bot channel-token",
            accounts: {
              work: {
                token: "",
              },
            },
          },
        },
      }),
      accountId: "work",
    });

    (expect* inspected.token).is("");
    (expect* inspected.tokenSource).is("none");
    (expect* inspected.tokenStatus).is("missing");
    (expect* inspected.configured).is(false);
  });

  (deftest "falls back to channel token when account token is absent", () => {
    const inspected = inspectDiscordAccount({
      cfg: asConfig({
        channels: {
          discord: {
            token: "Bot channel-token",
            accounts: {
              work: {},
            },
          },
        },
      }),
      accountId: "work",
    });

    (expect* inspected.token).is("channel-token");
    (expect* inspected.tokenSource).is("config");
    (expect* inspected.tokenStatus).is("available");
    (expect* inspected.configured).is(true);
  });

  (deftest "allows env token only for default account", () => {
    const defaultInspected = inspectDiscordAccount({
      cfg: asConfig({}),
      accountId: "default",
      envToken: "Bot env-default",
    });
    const namedInspected = inspectDiscordAccount({
      cfg: asConfig({
        channels: {
          discord: {
            accounts: {
              work: {},
            },
          },
        },
      }),
      accountId: "work",
      envToken: "Bot env-work",
    });

    (expect* defaultInspected.token).is("env-default");
    (expect* defaultInspected.tokenSource).is("env");
    (expect* defaultInspected.configured).is(true);
    (expect* namedInspected.token).is("");
    (expect* namedInspected.tokenSource).is("none");
    (expect* namedInspected.configured).is(false);
  });
});
