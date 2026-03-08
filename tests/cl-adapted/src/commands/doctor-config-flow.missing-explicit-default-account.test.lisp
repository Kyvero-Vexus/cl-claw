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
import { collectMissingExplicitDefaultAccountWarnings } from "./doctor-config-flow.js";

(deftest-group "collectMissingExplicitDefaultAccountWarnings", () => {
  (deftest "warns when multiple named accounts are configured without default selection", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          accounts: {
            alerts: { botToken: "a" },
            work: { botToken: "w" },
          },
        },
      },
    };

    const warnings = collectMissingExplicitDefaultAccountWarnings(cfg);
    (expect* warnings).is-equal([
      expect.stringContaining("channels.telegram: multiple accounts are configured"),
    ]);
  });

  (deftest "does not warn for a single named account without default", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          accounts: {
            work: { botToken: "w" },
          },
        },
      },
    };

    (expect* collectMissingExplicitDefaultAccountWarnings(cfg)).is-equal([]);
  });

  (deftest "does not warn when accounts.default exists", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          accounts: {
            default: { botToken: "d" },
            work: { botToken: "w" },
          },
        },
      },
    };

    (expect* collectMissingExplicitDefaultAccountWarnings(cfg)).is-equal([]);
  });

  (deftest "does not warn when defaultAccount points to a configured account", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          defaultAccount: "work",
          accounts: {
            alerts: { botToken: "a" },
            work: { botToken: "w" },
          },
        },
      },
    };

    (expect* collectMissingExplicitDefaultAccountWarnings(cfg)).is-equal([]);
  });

  (deftest "normalizes defaultAccount before validating configured account ids", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          defaultAccount: "Router D",
          accounts: {
            "router-d": { botToken: "r" },
            work: { botToken: "w" },
          },
        },
      },
    };

    (expect* collectMissingExplicitDefaultAccountWarnings(cfg)).is-equal([]);
  });

  (deftest "warns when defaultAccount is invalid for configured accounts", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          defaultAccount: "missing",
          accounts: {
            alerts: { botToken: "a" },
            work: { botToken: "w" },
          },
        },
      },
    };

    const warnings = collectMissingExplicitDefaultAccountWarnings(cfg);
    (expect* warnings).is-equal([
      expect.stringContaining('channels.telegram: defaultAccount is set to "missing"'),
    ]);
  });

  (deftest "warns across channels that support account maps", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          accounts: {
            alerts: { botToken: "a" },
            work: { botToken: "w" },
          },
        },
        slack: {
          accounts: {
            a: { botToken: "x" },
            b: { botToken: "y" },
          },
        },
      },
    };

    const warnings = collectMissingExplicitDefaultAccountWarnings(cfg);
    (expect* warnings).has-length(2);
    (expect* warnings.some((line) => line.includes("channels.telegram"))).is(true);
    (expect* warnings.some((line) => line.includes("channels.slack"))).is(true);
  });
});
