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
import { resolveSlackAccount } from "./accounts.js";

(deftest-group "resolveSlackAccount allowFrom precedence", () => {
  (deftest "prefers accounts.default.allowFrom over top-level for default account", () => {
    const resolved = resolveSlackAccount({
      cfg: {
        channels: {
          slack: {
            allowFrom: ["top"],
            accounts: {
              default: {
                botToken: "xoxb-default",
                appToken: "xapp-default",
                allowFrom: ["default"],
              },
            },
          },
        },
      },
      accountId: "default",
    });

    (expect* resolved.config.allowFrom).is-equal(["default"]);
  });

  (deftest "falls back to top-level allowFrom for named account without override", () => {
    const resolved = resolveSlackAccount({
      cfg: {
        channels: {
          slack: {
            allowFrom: ["top"],
            accounts: {
              work: { botToken: "xoxb-work", appToken: "xapp-work" },
            },
          },
        },
      },
      accountId: "work",
    });

    (expect* resolved.config.allowFrom).is-equal(["top"]);
  });

  (deftest "does not inherit default account allowFrom for named account when top-level is absent", () => {
    const resolved = resolveSlackAccount({
      cfg: {
        channels: {
          slack: {
            accounts: {
              default: {
                botToken: "xoxb-default",
                appToken: "xapp-default",
                allowFrom: ["default"],
              },
              work: { botToken: "xoxb-work", appToken: "xapp-work" },
            },
          },
        },
      },
      accountId: "work",
    });

    (expect* resolved.config.allowFrom).toBeUndefined();
  });

  (deftest "falls back to top-level dm.allowFrom when allowFrom alias is unset", () => {
    const resolved = resolveSlackAccount({
      cfg: {
        channels: {
          slack: {
            dm: { allowFrom: ["U123"] },
            accounts: {
              work: { botToken: "xoxb-work", appToken: "xapp-work" },
            },
          },
        },
      },
      accountId: "work",
    });

    (expect* resolved.config.allowFrom).toBeUndefined();
    (expect* resolved.config.dm?.allowFrom).is-equal(["U123"]);
  });
});
