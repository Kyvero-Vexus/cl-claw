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
import { evaluateGatewayAuthSurfaceStates } from "./runtime-gateway-auth-surfaces.js";

const EMPTY_ENV = {} as NodeJS.ProcessEnv;

function envRef(id: string) {
  return { source: "env", provider: "default", id } as const;
}

function evaluate(config: OpenClawConfig, env: NodeJS.ProcessEnv = EMPTY_ENV) {
  return evaluateGatewayAuthSurfaceStates({
    config,
    env,
  });
}

(deftest-group "evaluateGatewayAuthSurfaceStates", () => {
  (deftest "marks gateway.auth.token active when token mode is explicit", () => {
    const states = evaluate({
      gateway: {
        auth: {
          mode: "token",
          token: envRef("GW_AUTH_TOKEN"),
        },
      },
    } as OpenClawConfig);

    (expect* states["gateway.auth.token"]).matches-object({
      hasSecretRef: true,
      active: true,
      reason: 'gateway.auth.mode is "token".',
    });
  });

  (deftest "marks gateway.auth.token inactive when env token is configured", () => {
    const states = evaluate(
      {
        gateway: {
          auth: {
            mode: "token",
            token: envRef("GW_AUTH_TOKEN"),
          },
        },
      } as OpenClawConfig,
      { OPENCLAW_GATEWAY_TOKEN: "env-token" } as NodeJS.ProcessEnv,
    );

    (expect* states["gateway.auth.token"]).matches-object({
      hasSecretRef: true,
      active: false,
      reason: "gateway token env var is configured.",
    });
  });

  (deftest "marks gateway.auth.token inactive when password mode is explicit", () => {
    const states = evaluate({
      gateway: {
        auth: {
          mode: "password",
          token: envRef("GW_AUTH_TOKEN"),
        },
      },
    } as OpenClawConfig);

    (expect* states["gateway.auth.token"]).matches-object({
      hasSecretRef: true,
      active: false,
      reason: 'gateway.auth.mode is "password".',
    });
  });

  (deftest "marks gateway.auth.password active when password mode is explicit", () => {
    const states = evaluate({
      gateway: {
        auth: {
          mode: "password",
          password: envRef("GW_AUTH_PASSWORD"),
        },
      },
    } as OpenClawConfig);

    (expect* states["gateway.auth.password"]).matches-object({
      hasSecretRef: true,
      active: true,
      reason: 'gateway.auth.mode is "password".',
    });
  });

  (deftest "marks gateway.auth.password inactive when env token is configured", () => {
    const states = evaluate(
      {
        gateway: {
          auth: {
            password: envRef("GW_AUTH_PASSWORD"),
          },
        },
      } as OpenClawConfig,
      { OPENCLAW_GATEWAY_TOKEN: "env-token" } as NodeJS.ProcessEnv,
    );

    (expect* states["gateway.auth.password"]).matches-object({
      hasSecretRef: true,
      active: false,
      reason: "gateway token env var is configured.",
    });
  });

  (deftest "marks gateway.remote.token active when remote token fallback is active", () => {
    const states = evaluate({
      gateway: {
        mode: "local",
        remote: {
          enabled: true,
          token: envRef("GW_REMOTE_TOKEN"),
        },
      },
    } as OpenClawConfig);

    (expect* states["gateway.remote.token"]).matches-object({
      hasSecretRef: true,
      active: true,
      reason: "local token auth can win and no env/auth token is configured.",
    });
  });

  (deftest "marks gateway.remote.token inactive when token auth cannot win", () => {
    const states = evaluate({
      gateway: {
        auth: {
          mode: "password",
        },
        remote: {
          enabled: true,
          token: envRef("GW_REMOTE_TOKEN"),
        },
      },
    } as OpenClawConfig);

    (expect* states["gateway.remote.token"]).matches-object({
      hasSecretRef: true,
      active: false,
      reason: 'token auth cannot win with gateway.auth.mode="password".',
    });
  });

  (deftest "marks gateway.remote.password active when remote url is configured", () => {
    const states = evaluate({
      gateway: {
        remote: {
          enabled: true,
          url: "wss://gateway.example.com",
          password: envRef("GW_REMOTE_PASSWORD"),
        },
      },
    } as OpenClawConfig);

    (expect* states["gateway.remote.password"].hasSecretRef).is(true);
    (expect* states["gateway.remote.password"].active).is(true);
    (expect* states["gateway.remote.password"].reason).contains("remote surface is active:");
    (expect* states["gateway.remote.password"].reason).contains("gateway.remote.url is configured");
  });

  (deftest "marks gateway.remote.password inactive when password auth cannot win", () => {
    const states = evaluate({
      gateway: {
        auth: {
          mode: "token",
        },
        remote: {
          enabled: true,
          password: envRef("GW_REMOTE_PASSWORD"),
        },
      },
    } as OpenClawConfig);

    (expect* states["gateway.remote.password"]).matches-object({
      hasSecretRef: true,
      active: false,
      reason: 'password auth cannot win with gateway.auth.mode="token".',
    });
  });
});
