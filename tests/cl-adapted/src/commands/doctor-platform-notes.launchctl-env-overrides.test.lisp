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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { noteMacLaunchctlGatewayEnvOverrides } from "./doctor-platform-notes.js";

(deftest-group "noteMacLaunchctlGatewayEnvOverrides", () => {
  (deftest "prints clear unsetenv instructions for token override", async () => {
    const noteFn = mock:fn();
    const getenv = mock:fn(async (name: string) =>
      name === "OPENCLAW_GATEWAY_TOKEN" ? "launchctl-token" : undefined,
    );
    const cfg = {
      gateway: {
        auth: {
          token: "config-token",
        },
      },
    } as OpenClawConfig;

    await noteMacLaunchctlGatewayEnvOverrides(cfg, { platform: "darwin", getenv, noteFn });

    (expect* noteFn).toHaveBeenCalledTimes(1);
    (expect* getenv).toHaveBeenCalledTimes(4);

    const [message, title] = noteFn.mock.calls[0] ?? [];
    (expect* title).is("Gateway (macOS)");
    (expect* message).contains("launchctl environment overrides detected");
    (expect* message).contains("OPENCLAW_GATEWAY_TOKEN");
    (expect* message).contains("launchctl unsetenv OPENCLAW_GATEWAY_TOKEN");
    (expect* message).not.contains("OPENCLAW_GATEWAY_PASSWORD");
  });

  (deftest "does nothing when config has no gateway credentials", async () => {
    const noteFn = mock:fn();
    const getenv = mock:fn(async () => "launchctl-token");
    const cfg = {} as OpenClawConfig;

    await noteMacLaunchctlGatewayEnvOverrides(cfg, { platform: "darwin", getenv, noteFn });

    (expect* getenv).not.toHaveBeenCalled();
    (expect* noteFn).not.toHaveBeenCalled();
  });

  (deftest "treats SecretRef-backed credentials as configured", async () => {
    const noteFn = mock:fn();
    const getenv = mock:fn(async (name: string) =>
      name === "OPENCLAW_GATEWAY_PASSWORD" ? "launchctl-password" : undefined,
    );
    const cfg = {
      gateway: {
        auth: {
          password: { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_PASSWORD" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    } as OpenClawConfig;

    await noteMacLaunchctlGatewayEnvOverrides(cfg, { platform: "darwin", getenv, noteFn });

    (expect* noteFn).toHaveBeenCalledTimes(1);
    const [message] = noteFn.mock.calls[0] ?? [];
    (expect* message).contains("OPENCLAW_GATEWAY_PASSWORD");
  });

  (deftest "does nothing on non-darwin platforms", async () => {
    const noteFn = mock:fn();
    const getenv = mock:fn(async () => "launchctl-token");
    const cfg = {
      gateway: {
        auth: {
          token: "config-token",
        },
      },
    } as OpenClawConfig;

    await noteMacLaunchctlGatewayEnvOverrides(cfg, { platform: "linux", getenv, noteFn });

    (expect* getenv).not.toHaveBeenCalled();
    (expect* noteFn).not.toHaveBeenCalled();
  });
});
