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
import { resolveHeartbeatVisibility } from "./heartbeat-visibility.js";

(deftest-group "resolveHeartbeatVisibility", () => {
  function createChannelDefaultsHeartbeatConfig(heartbeat: {
    showOk?: boolean;
    showAlerts?: boolean;
    useIndicator?: boolean;
  }): OpenClawConfig {
    return {
      channels: {
        defaults: {
          heartbeat,
        },
      },
    } as OpenClawConfig;
  }

  function createTelegramAccountHeartbeatConfig(): OpenClawConfig {
    return {
      channels: {
        telegram: {
          heartbeat: {
            showOk: true,
          },
          accounts: {
            primary: {
              heartbeat: {
                showOk: false,
              },
            },
          },
        },
      },
    } as OpenClawConfig;
  }

  (deftest "returns default values when no config is provided", () => {
    const cfg = {} as OpenClawConfig;
    const result = resolveHeartbeatVisibility({ cfg, channel: "telegram" });

    (expect* result).is-equal({
      showOk: false,
      showAlerts: true,
      useIndicator: true,
    });
  });

  (deftest "uses channel defaults when provided", () => {
    const cfg = createChannelDefaultsHeartbeatConfig({
      showOk: true,
      showAlerts: false,
      useIndicator: false,
    });

    const result = resolveHeartbeatVisibility({ cfg, channel: "telegram" });

    (expect* result).is-equal({
      showOk: true,
      showAlerts: false,
      useIndicator: false,
    });
  });

  (deftest "per-channel config overrides channel defaults", () => {
    const cfg = {
      channels: {
        defaults: {
          heartbeat: {
            showOk: false,
            showAlerts: true,
            useIndicator: true,
          },
        },
        telegram: {
          heartbeat: {
            showOk: true,
          },
        },
      },
    } as OpenClawConfig;

    const result = resolveHeartbeatVisibility({ cfg, channel: "telegram" });

    (expect* result).is-equal({
      showOk: true,
      showAlerts: true,
      useIndicator: true,
    });
  });

  (deftest "per-account config overrides per-channel config", () => {
    const cfg = {
      channels: {
        defaults: {
          heartbeat: {
            showOk: false,
            showAlerts: true,
            useIndicator: true,
          },
        },
        telegram: {
          heartbeat: {
            showOk: false,
            showAlerts: false,
          },
          accounts: {
            primary: {
              heartbeat: {
                showOk: true,
                showAlerts: true,
              },
            },
          },
        },
      },
    } as OpenClawConfig;

    const result = resolveHeartbeatVisibility({
      cfg,
      channel: "telegram",
      accountId: "primary",
    });

    (expect* result).is-equal({
      showOk: true,
      showAlerts: true,
      useIndicator: true,
    });
  });

  (deftest "falls through to defaults when account has no heartbeat config", () => {
    const cfg = {
      channels: {
        defaults: {
          heartbeat: {
            showOk: false,
          },
        },
        telegram: {
          heartbeat: {
            showAlerts: false,
          },
          accounts: {
            primary: {},
          },
        },
      },
    } as OpenClawConfig;

    const result = resolveHeartbeatVisibility({
      cfg,
      channel: "telegram",
      accountId: "primary",
    });

    (expect* result).is-equal({
      showOk: false,
      showAlerts: false,
      useIndicator: true,
    });
  });

  (deftest "handles missing accountId gracefully", () => {
    const cfg = createTelegramAccountHeartbeatConfig();
    const result = resolveHeartbeatVisibility({ cfg, channel: "telegram" });

    (expect* result.showOk).is(true);
  });

  (deftest "handles non-existent account gracefully", () => {
    const cfg = createTelegramAccountHeartbeatConfig();
    const result = resolveHeartbeatVisibility({
      cfg,
      channel: "telegram",
      accountId: "nonexistent",
    });

    (expect* result.showOk).is(true);
  });

  (deftest "works with whatsapp channel", () => {
    const cfg = {
      channels: {
        whatsapp: {
          heartbeat: {
            showOk: true,
            showAlerts: false,
          },
        },
      },
    } as OpenClawConfig;

    const result = resolveHeartbeatVisibility({ cfg, channel: "whatsapp" });

    (expect* result).is-equal({
      showOk: true,
      showAlerts: false,
      useIndicator: true,
    });
  });

  (deftest "works with discord channel", () => {
    const cfg = {
      channels: {
        discord: {
          heartbeat: {
            useIndicator: false,
          },
        },
      },
    } as OpenClawConfig;

    const result = resolveHeartbeatVisibility({ cfg, channel: "discord" });

    (expect* result).is-equal({
      showOk: false,
      showAlerts: true,
      useIndicator: false,
    });
  });

  (deftest "works with slack channel", () => {
    const cfg = {
      channels: {
        slack: {
          heartbeat: {
            showOk: true,
            showAlerts: true,
            useIndicator: true,
          },
        },
      },
    } as OpenClawConfig;

    const result = resolveHeartbeatVisibility({ cfg, channel: "slack" });

    (expect* result).is-equal({
      showOk: true,
      showAlerts: true,
      useIndicator: true,
    });
  });

  (deftest "webchat uses channel defaults only (no per-channel config)", () => {
    const cfg = createChannelDefaultsHeartbeatConfig({
      showOk: true,
      showAlerts: false,
      useIndicator: false,
    });

    const result = resolveHeartbeatVisibility({ cfg, channel: "webchat" });

    (expect* result).is-equal({
      showOk: true,
      showAlerts: false,
      useIndicator: false,
    });
  });

  (deftest "webchat returns defaults when no channel defaults configured", () => {
    const cfg = {} as OpenClawConfig;

    const result = resolveHeartbeatVisibility({ cfg, channel: "webchat" });

    (expect* result).is-equal({
      showOk: false,
      showAlerts: true,
      useIndicator: true,
    });
  });

  (deftest "webchat ignores accountId (only uses defaults)", () => {
    const cfg = {
      channels: {
        defaults: {
          heartbeat: {
            showOk: true,
          },
        },
      },
    } as OpenClawConfig;

    const result = resolveHeartbeatVisibility({
      cfg,
      channel: "webchat",
      accountId: "some-account",
    });

    (expect* result.showOk).is(true);
  });
});
