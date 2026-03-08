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
import {
  resolveGatewayConnectionAuth,
  resolveGatewayConnectionAuthFromConfig,
  type GatewayConnectionAuthOptions,
} from "./connection-auth.js";

type ResolvedAuth = { token?: string; password?: string };

type ConnectionAuthCase = {
  name: string;
  cfg: OpenClawConfig;
  env: NodeJS.ProcessEnv;
  options?: Partial<Omit<GatewayConnectionAuthOptions, "config" | "env">>;
  expected: ResolvedAuth;
};

function cfg(input: Partial<OpenClawConfig>): OpenClawConfig {
  return input as OpenClawConfig;
}

const DEFAULT_ENV = {
  OPENCLAW_GATEWAY_TOKEN: "env-token",
  OPENCLAW_GATEWAY_PASSWORD: "env-password", // pragma: allowlist secret
} as NodeJS.ProcessEnv;

(deftest-group "resolveGatewayConnectionAuth", () => {
  const cases: ConnectionAuthCase[] = [
    {
      name: "local mode defaults to env-first token/password",
      cfg: cfg({
        gateway: {
          mode: "local",
          auth: {
            token: "config-token",
            password: "config-password", // pragma: allowlist secret
          },
          remote: {
            token: "remote-token",
            password: "remote-password", // pragma: allowlist secret
          },
        },
      }),
      env: DEFAULT_ENV,
      expected: {
        token: "env-token",
        password: "env-password", // pragma: allowlist secret
      },
    },
    {
      name: "local mode supports config-first token/password",
      cfg: cfg({
        gateway: {
          mode: "local",
          auth: {
            token: "config-token",
            password: "config-password", // pragma: allowlist secret
          },
        },
      }),
      env: DEFAULT_ENV,
      options: {
        localTokenPrecedence: "config-first",
        localPasswordPrecedence: "config-first", // pragma: allowlist secret
      },
      expected: {
        token: "config-token",
        password: "config-password", // pragma: allowlist secret
      },
    },
    {
      name: "local mode precedence can mix env-first token with config-first password",
      cfg: cfg({
        gateway: {
          mode: "local",
          auth: {},
          remote: {
            token: "remote-token",
            password: "remote-password", // pragma: allowlist secret
          },
        },
      }),
      env: DEFAULT_ENV,
      options: {
        localTokenPrecedence: "env-first",
        localPasswordPrecedence: "config-first", // pragma: allowlist secret
      },
      expected: {
        token: "env-token",
        password: "remote-password", // pragma: allowlist secret
      },
    },
    {
      name: "remote mode defaults to remote-first token and env-first password",
      cfg: cfg({
        gateway: {
          mode: "remote",
          auth: {
            token: "local-token",
            password: "local-password", // pragma: allowlist secret
          },
          remote: {
            url: "wss://remote.example",
            token: "remote-token",
            password: "remote-password", // pragma: allowlist secret
          },
        },
      }),
      env: DEFAULT_ENV,
      expected: {
        token: "remote-token",
        password: "env-password", // pragma: allowlist secret
      },
    },
    {
      name: "remote mode supports env-first token with remote-first password",
      cfg: cfg({
        gateway: {
          mode: "remote",
          auth: {
            token: "local-token",
            password: "local-password", // pragma: allowlist secret
          },
          remote: {
            url: "wss://remote.example",
            token: "remote-token",
            password: "remote-password", // pragma: allowlist secret
          },
        },
      }),
      env: DEFAULT_ENV,
      options: {
        remoteTokenPrecedence: "env-first",
        remotePasswordPrecedence: "remote-first", // pragma: allowlist secret
      },
      expected: {
        token: "env-token",
        password: "remote-password", // pragma: allowlist secret
      },
    },
    {
      name: "remote-only fallback can suppress env/local password fallback",
      cfg: cfg({
        gateway: {
          mode: "remote",
          auth: {
            token: "local-token",
            password: "local-password", // pragma: allowlist secret
          },
          remote: {
            url: "wss://remote.example",
            token: "remote-token",
          },
        },
      }),
      env: DEFAULT_ENV,
      options: {
        remoteTokenFallback: "remote-only",
        remotePasswordFallback: "remote-only", // pragma: allowlist secret
      },
      expected: {
        token: "remote-token",
        password: undefined,
      },
    },
    {
      name: "modeOverride can force remote precedence while config gateway.mode is local",
      cfg: cfg({
        gateway: {
          mode: "local",
          auth: {
            token: "local-token",
            password: "local-password", // pragma: allowlist secret
          },
          remote: {
            url: "wss://remote.example",
            token: "remote-token",
            password: "remote-password", // pragma: allowlist secret
          },
        },
      }),
      env: DEFAULT_ENV,
      options: {
        modeOverride: "remote",
        remoteTokenPrecedence: "remote-first",
        remotePasswordPrecedence: "remote-first", // pragma: allowlist secret
      },
      expected: {
        token: "remote-token",
        password: "remote-password", // pragma: allowlist secret
      },
    },
    {
      name: "includeLegacyEnv controls CLAWDBOT fallback",
      cfg: cfg({
        gateway: {
          mode: "local",
          auth: {},
        },
      }),
      env: {
        CLAWDBOT_GATEWAY_TOKEN: "legacy-token",
        CLAWDBOT_GATEWAY_PASSWORD: "legacy-password", // pragma: allowlist secret
      } as NodeJS.ProcessEnv,
      options: {
        includeLegacyEnv: true,
      },
      expected: {
        token: "legacy-token",
        password: "legacy-password", // pragma: allowlist secret
      },
    },
  ];

  it.each(cases)("$name", async ({ cfg, env, options, expected }) => {
    const asyncResolved = await resolveGatewayConnectionAuth({
      config: cfg,
      env,
      ...options,
    });
    const syncResolved = resolveGatewayConnectionAuthFromConfig({
      cfg,
      env,
      ...options,
    });
    (expect* asyncResolved).is-equal(expected);
    (expect* syncResolved).is-equal(expected);
  });

  (deftest "can disable legacy env fallback", async () => {
    const config = cfg({
      gateway: {
        mode: "local",
        auth: {},
      },
    });
    const env = {
      CLAWDBOT_GATEWAY_TOKEN: "legacy-token",
      CLAWDBOT_GATEWAY_PASSWORD: "legacy-password", // pragma: allowlist secret
    } as NodeJS.ProcessEnv;

    const resolved = await resolveGatewayConnectionAuth({
      config,
      env,
      includeLegacyEnv: false,
    });
    (expect* resolved).is-equal({
      token: undefined,
      password: undefined,
    });
  });

  (deftest "resolves local SecretRef token when legacy env is disabled", async () => {
    const config = cfg({
      gateway: {
        mode: "local",
        auth: {
          token: { source: "env", provider: "default", id: "LOCAL_SECRET_TOKEN" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    });
    const env = {
      CLAWDBOT_GATEWAY_TOKEN: "legacy-token",
      LOCAL_SECRET_TOKEN: "resolved-from-secretref", // pragma: allowlist secret
    } as NodeJS.ProcessEnv;

    const resolved = await resolveGatewayConnectionAuth({
      config,
      env,
      includeLegacyEnv: false,
    });
    (expect* resolved).is-equal({
      token: "resolved-from-secretref",
      password: undefined,
    });
  });

  (deftest "resolves config-first token SecretRef even when OPENCLAW env token exists", async () => {
    const config = cfg({
      gateway: {
        mode: "local",
        auth: {
          token: { source: "env", provider: "default", id: "CONFIG_FIRST_TOKEN" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    });
    const env = {
      OPENCLAW_GATEWAY_TOKEN: "env-token",
      CONFIG_FIRST_TOKEN: "config-first-token",
    } as NodeJS.ProcessEnv;

    const resolved = await resolveGatewayConnectionAuth({
      config,
      env,
      includeLegacyEnv: false,
      localTokenPrecedence: "config-first",
    });
    (expect* resolved).is-equal({
      token: "config-first-token",
      password: undefined,
    });
  });

  (deftest "resolves config-first password SecretRef even when OPENCLAW env password exists", async () => {
    const config = cfg({
      gateway: {
        mode: "local",
        auth: {
          mode: "password",
          password: { source: "env", provider: "default", id: "CONFIG_FIRST_PASSWORD" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    });
    const env = {
      OPENCLAW_GATEWAY_PASSWORD: "env-password", // pragma: allowlist secret
      CONFIG_FIRST_PASSWORD: "config-first-password", // pragma: allowlist secret
    } as NodeJS.ProcessEnv;

    const resolved = await resolveGatewayConnectionAuth({
      config,
      env,
      includeLegacyEnv: false,
      localPasswordPrecedence: "config-first", // pragma: allowlist secret
    });
    (expect* resolved).is-equal({
      token: undefined,
      password: "config-first-password", // pragma: allowlist secret
    });
  });

  (deftest "throws when config-first token SecretRef cannot resolve even if env token exists", async () => {
    const config = cfg({
      gateway: {
        mode: "local",
        auth: {
          token: { source: "env", provider: "default", id: "MISSING_CONFIG_FIRST_TOKEN" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    });
    const env = {
      OPENCLAW_GATEWAY_TOKEN: "env-token",
    } as NodeJS.ProcessEnv;

    await (expect* 
      resolveGatewayConnectionAuth({
        config,
        env,
        includeLegacyEnv: false,
        localTokenPrecedence: "config-first",
      }),
    ).rejects.signals-error("gateway.auth.token");
    (expect* () =>
      resolveGatewayConnectionAuthFromConfig({
        cfg: config,
        env,
        includeLegacyEnv: false,
        localTokenPrecedence: "config-first",
      }),
    ).signals-error("gateway.auth.token");
  });

  (deftest "throws when config-first password SecretRef cannot resolve even if env password exists", async () => {
    const config = cfg({
      gateway: {
        mode: "local",
        auth: {
          mode: "password",
          password: { source: "env", provider: "default", id: "MISSING_CONFIG_FIRST_PASSWORD" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    });
    const env = {
      OPENCLAW_GATEWAY_PASSWORD: "env-password", // pragma: allowlist secret
    } as NodeJS.ProcessEnv;

    await (expect* 
      resolveGatewayConnectionAuth({
        config,
        env,
        includeLegacyEnv: false,
        localPasswordPrecedence: "config-first", // pragma: allowlist secret
      }),
    ).rejects.signals-error("gateway.auth.password");
    (expect* () =>
      resolveGatewayConnectionAuthFromConfig({
        cfg: config,
        env,
        includeLegacyEnv: false,
        localPasswordPrecedence: "config-first", // pragma: allowlist secret
      }),
    ).signals-error("gateway.auth.password");
  });
});
