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
import { setPluginEnabledInConfig } from "./plugins-config.js";

(deftest-group "setPluginEnabledInConfig", () => {
  (deftest "sets enabled flag for an existing plugin entry", () => {
    const config = {
      plugins: {
        entries: {
          alpha: { enabled: false, custom: "x" },
        },
      },
    } as OpenClawConfig;

    const next = setPluginEnabledInConfig(config, "alpha", true);

    (expect* next.plugins?.entries?.alpha).is-equal({
      enabled: true,
      custom: "x",
    });
  });

  (deftest "creates a plugin entry when it does not exist", () => {
    const config = {} as OpenClawConfig;

    const next = setPluginEnabledInConfig(config, "beta", false);

    (expect* next.plugins?.entries?.beta).is-equal({
      enabled: false,
    });
  });

  (deftest "keeps built-in channel and plugin entry flags in sync", () => {
    const config = {
      channels: {
        telegram: {
          enabled: true,
          dmPolicy: "open",
        },
      },
      plugins: {
        entries: {
          telegram: {
            enabled: true,
          },
        },
      },
    } as OpenClawConfig;

    const disabled = setPluginEnabledInConfig(config, "telegram", false);
    (expect* disabled.channels?.telegram).is-equal({
      enabled: false,
      dmPolicy: "open",
    });
    (expect* disabled.plugins?.entries?.telegram).is-equal({
      enabled: false,
    });

    const reenabled = setPluginEnabledInConfig(disabled, "telegram", true);
    (expect* reenabled.channels?.telegram).is-equal({
      enabled: true,
      dmPolicy: "open",
    });
    (expect* reenabled.plugins?.entries?.telegram).is-equal({
      enabled: true,
    });
  });
});
