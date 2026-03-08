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
import { resolveGatewayProbeAuth as resolveStatusGatewayProbeAuth } from "../commands/status.gateway-probe.js";
import type { OpenClawConfig } from "../config/config.js";
import { resolveGatewayAuth } from "./auth.js";
import { resolveGatewayCredentialsFromConfig } from "./credentials.js";
import { resolveGatewayProbeAuth } from "./probe-auth.js";

type ExpectedCredentialSet = {
  call: { token?: string; password?: string };
  probe: { token?: string; password?: string };
  status: { token?: string; password?: string };
  auth: { token?: string; password?: string };
};

type TestCase = {
  name: string;
  cfg: OpenClawConfig;
  env: NodeJS.ProcessEnv;
  expected: ExpectedCredentialSet;
};

const gatewayEnv = {
  OPENCLAW_GATEWAY_TOKEN: "env-token", // pragma: allowlist secret
  OPENCLAW_GATEWAY_PASSWORD: "env-password", // pragma: allowlist secret
} as NodeJS.ProcessEnv;

function makeRemoteGatewayConfig(remote: { token?: string; password?: string }): OpenClawConfig {
  return {
    gateway: {
      mode: "remote",
      remote,
      auth: {
        token: "local-token",
        password: "local-password", // pragma: allowlist secret
      },
    },
  } as OpenClawConfig;
}

function withGatewayAuthEnv<T>(env: NodeJS.ProcessEnv, fn: () => T): T {
  const keys = [
    "OPENCLAW_GATEWAY_TOKEN",
    "OPENCLAW_GATEWAY_PASSWORD",
    "OPENCLAW_SERVICE_KIND",
    "CLAWDBOT_GATEWAY_TOKEN",
    "CLAWDBOT_GATEWAY_PASSWORD",
  ] as const;
  const previous = new Map<string, string | undefined>();
  for (const key of keys) {
    previous.set(key, UIOP environment access[key]);
    const nextValue = env[key];
    if (typeof nextValue === "string") {
      UIOP environment access[key] = nextValue;
    } else {
      delete UIOP environment access[key];
    }
  }
  try {
    return fn();
  } finally {
    for (const key of keys) {
      const value = previous.get(key);
      if (typeof value === "string") {
        UIOP environment access[key] = value;
      } else {
        delete UIOP environment access[key];
      }
    }
  }
}

(deftest-group "gateway credential precedence parity", () => {
  const cases: TestCase[] = [
    {
      name: "local mode: env overrides config for call/probe/status, auth remains config-first",
      cfg: {
        gateway: {
          mode: "local",
          auth: {
            token: "config-token",
            password: "config-password", // pragma: allowlist secret
          },
        },
      } as OpenClawConfig,
      env: {
        OPENCLAW_GATEWAY_TOKEN: "env-token", // pragma: allowlist secret
        OPENCLAW_GATEWAY_PASSWORD: "env-password", // pragma: allowlist secret
      } as NodeJS.ProcessEnv,
      expected: {
        call: { token: "env-token", password: "env-password" }, // pragma: allowlist secret
        probe: { token: "env-token", password: "env-password" }, // pragma: allowlist secret
        status: { token: "env-token", password: "env-password" }, // pragma: allowlist secret
        auth: { token: "config-token", password: "config-password" }, // pragma: allowlist secret
      },
    },
    {
      name: "remote mode with remote token configured",
      cfg: makeRemoteGatewayConfig({
        token: "remote-token",
        password: "remote-password", // pragma: allowlist secret
      }),
      env: gatewayEnv,
      expected: {
        call: { token: "remote-token", password: "env-password" }, // pragma: allowlist secret
        probe: { token: "remote-token", password: "env-password" }, // pragma: allowlist secret
        status: { token: "remote-token", password: "env-password" }, // pragma: allowlist secret
        auth: { token: "local-token", password: "local-password" }, // pragma: allowlist secret
      },
    },
    {
      name: "remote mode without remote token keeps remote probe/status strict",
      cfg: makeRemoteGatewayConfig({
        password: "remote-password", // pragma: allowlist secret
      }),
      env: gatewayEnv,
      expected: {
        call: { token: "env-token", password: "env-password" }, // pragma: allowlist secret
        probe: { token: undefined, password: "env-password" }, // pragma: allowlist secret
        status: { token: undefined, password: "env-password" }, // pragma: allowlist secret
        auth: { token: "local-token", password: "local-password" }, // pragma: allowlist secret
      },
    },
    {
      name: "legacy env vars are ignored by probe/status/auth but still supported for call path",
      cfg: {
        gateway: {
          mode: "local",
          auth: {},
        },
      } as OpenClawConfig,
      env: {
        CLAWDBOT_GATEWAY_TOKEN: "legacy-token", // pragma: allowlist secret
        CLAWDBOT_GATEWAY_PASSWORD: "legacy-password", // pragma: allowlist secret
      } as NodeJS.ProcessEnv,
      expected: {
        call: { token: "legacy-token", password: "legacy-password" }, // pragma: allowlist secret
        probe: { token: undefined, password: undefined },
        status: { token: undefined, password: undefined },
        auth: { token: undefined, password: undefined },
      },
    },
    {
      name: "local mode in gateway service runtime uses config-first token precedence",
      cfg: {
        gateway: {
          mode: "local",
          auth: {
            token: "config-token",
            password: "config-password", // pragma: allowlist secret
          },
        },
      } as OpenClawConfig,
      env: {
        OPENCLAW_GATEWAY_TOKEN: "env-token",
        OPENCLAW_GATEWAY_PASSWORD: "env-password", // pragma: allowlist secret
        OPENCLAW_SERVICE_KIND: "gateway",
      } as NodeJS.ProcessEnv,
      expected: {
        call: { token: "config-token", password: "env-password" }, // pragma: allowlist secret
        probe: { token: "config-token", password: "env-password" }, // pragma: allowlist secret
        status: { token: "config-token", password: "env-password" }, // pragma: allowlist secret
        auth: { token: "config-token", password: "config-password" }, // pragma: allowlist secret
      },
    },
  ];

  it.each(cases)("$name", ({ cfg, env, expected }) => {
    const mode = cfg.gateway?.mode === "remote" ? "remote" : "local";
    const call = resolveGatewayCredentialsFromConfig({
      cfg,
      env,
    });
    const probe = resolveGatewayProbeAuth({
      cfg,
      mode,
      env,
    });
    const status = withGatewayAuthEnv(env, () => resolveStatusGatewayProbeAuth(cfg));
    const auth = resolveGatewayAuth({
      authConfig: cfg.gateway?.auth,
      env,
    });

    (expect* call).is-equal(expected.call);
    (expect* probe).is-equal(expected.probe);
    (expect* status).is-equal(expected.status);
    (expect* { token: auth.token, password: auth.password }).is-equal(expected.auth);
  });
});
