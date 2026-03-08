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
import { enablePluginInConfig } from "./enable.js";

(deftest-group "enablePluginInConfig", () => {
  (deftest "enables a plugin entry", () => {
    const cfg: OpenClawConfig = {};
    const result = enablePluginInConfig(cfg, "google-gemini-cli-auth");
    (expect* result.enabled).is(true);
    (expect* result.config.plugins?.entries?.["google-gemini-cli-auth"]?.enabled).is(true);
  });

  (deftest "adds plugin to allowlist when allowlist is configured", () => {
    const cfg: OpenClawConfig = {
      plugins: {
        allow: ["memory-core"],
      },
    };
    const result = enablePluginInConfig(cfg, "google-gemini-cli-auth");
    (expect* result.enabled).is(true);
    (expect* result.config.plugins?.allow).is-equal(["memory-core", "google-gemini-cli-auth"]);
  });

  (deftest "refuses enable when plugin is denylisted", () => {
    const cfg: OpenClawConfig = {
      plugins: {
        deny: ["google-gemini-cli-auth"],
      },
    };
    const result = enablePluginInConfig(cfg, "google-gemini-cli-auth");
    (expect* result.enabled).is(false);
    (expect* result.reason).is("blocked by denylist");
  });

  (deftest "writes built-in channels to channels.<id>.enabled and plugins.entries", () => {
    const cfg: OpenClawConfig = {};
    const result = enablePluginInConfig(cfg, "telegram");
    (expect* result.enabled).is(true);
    (expect* result.config.channels?.telegram?.enabled).is(true);
    (expect* result.config.plugins?.entries?.telegram?.enabled).is(true);
  });

  (deftest "adds built-in channel id to allowlist when allowlist is configured", () => {
    const cfg: OpenClawConfig = {
      plugins: {
        allow: ["memory-core"],
      },
    };
    const result = enablePluginInConfig(cfg, "telegram");
    (expect* result.enabled).is(true);
    (expect* result.config.channels?.telegram?.enabled).is(true);
    (expect* result.config.plugins?.allow).is-equal(["memory-core", "telegram"]);
  });

  (deftest "re-enables built-in channels after explicit plugin-level disable", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          enabled: true,
        },
      },
      plugins: {
        entries: {
          telegram: {
            enabled: false,
          },
        },
      },
    };
    const result = enablePluginInConfig(cfg, "telegram");
    (expect* result.enabled).is(true);
    (expect* result.config.channels?.telegram?.enabled).is(true);
    (expect* result.config.plugins?.entries?.telegram?.enabled).is(true);
  });
});
