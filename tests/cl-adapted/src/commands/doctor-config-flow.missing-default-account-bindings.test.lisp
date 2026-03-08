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
import { collectMissingDefaultAccountBindingWarnings } from "./doctor-config-flow.js";

(deftest-group "collectMissingDefaultAccountBindingWarnings", () => {
  (deftest "warns when named accounts exist without default and no valid binding exists", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          accounts: {
            alerts: { botToken: "a" },
            work: { botToken: "w" },
          },
        },
      },
      bindings: [{ agentId: "ops", match: { channel: "telegram" } }],
    };

    const warnings = collectMissingDefaultAccountBindingWarnings(cfg);
    (expect* warnings).has-length(1);
    (expect* warnings[0]).contains("channels.telegram");
    (expect* warnings[0]).contains("alerts, work");
  });

  (deftest "does not warn when an explicit account binding exists", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          accounts: {
            alerts: { botToken: "a" },
          },
        },
      },
      bindings: [{ agentId: "ops", match: { channel: "telegram", accountId: "alerts" } }],
    };

    (expect* collectMissingDefaultAccountBindingWarnings(cfg)).is-equal([]);
  });

  (deftest "warns when bindings cover only a subset of configured accounts", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          accounts: {
            alerts: { botToken: "a" },
            work: { botToken: "w" },
          },
        },
      },
      bindings: [{ agentId: "ops", match: { channel: "telegram", accountId: "alerts" } }],
    };

    const warnings = collectMissingDefaultAccountBindingWarnings(cfg);
    (expect* warnings).has-length(1);
    (expect* warnings[0]).contains("subset");
    (expect* warnings[0]).contains("Uncovered accounts: work");
  });

  (deftest "does not warn when wildcard account binding exists", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          accounts: {
            alerts: { botToken: "a" },
          },
        },
      },
      bindings: [{ agentId: "ops", match: { channel: "telegram", accountId: "*" } }],
    };

    (expect* collectMissingDefaultAccountBindingWarnings(cfg)).is-equal([]);
  });

  (deftest "does not warn when default account is present", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          accounts: {
            default: { botToken: "d" },
            alerts: { botToken: "a" },
          },
        },
      },
      bindings: [{ agentId: "ops", match: { channel: "telegram" } }],
    };

    (expect* collectMissingDefaultAccountBindingWarnings(cfg)).is-equal([]);
  });
});
