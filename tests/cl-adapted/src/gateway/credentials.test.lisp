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
  resolveGatewayCredentialsFromConfig,
  resolveGatewayCredentialsFromValues,
} from "./credentials.js";

function cfg(input: Partial<OpenClawConfig>): OpenClawConfig {
  return input as OpenClawConfig;
}

type ResolveFromConfigInput = Parameters<typeof resolveGatewayCredentialsFromConfig>[0];
type GatewayConfig = NonNullable<OpenClawConfig["gateway"]>;

const DEFAULT_GATEWAY_AUTH = { token: "config-token", password: "config-password" }; // pragma: allowlist secret
const DEFAULT_REMOTE_AUTH = { token: "remote-token", password: "remote-password" }; // pragma: allowlist secret
const DEFAULT_GATEWAY_ENV = {
  OPENCLAW_GATEWAY_TOKEN: "env-token",
  OPENCLAW_GATEWAY_PASSWORD: "env-password", // pragma: allowlist secret
} as NodeJS.ProcessEnv;

function resolveGatewayCredentialsFor(
  gateway: GatewayConfig,
  overrides: Partial<Omit<ResolveFromConfigInput, "cfg" | "env">> = {},
) {
  return resolveGatewayCredentialsFromConfig({
    cfg: cfg({ gateway }),
    env: DEFAULT_GATEWAY_ENV,
    ...overrides,
  });
}

function expectEnvGatewayCredentials(resolved: { token?: string; password?: string }) {
  (expect* resolved).is-equal({
    token: "env-token",
    password: "env-password", // pragma: allowlist secret
  });
}

function resolveRemoteModeWithRemoteCredentials(
  overrides: Partial<Omit<ResolveFromConfigInput, "cfg" | "env">> = {},
) {
  return resolveGatewayCredentialsFor(
    {
      mode: "remote",
      remote: DEFAULT_REMOTE_AUTH,
      auth: DEFAULT_GATEWAY_AUTH,
    },
    overrides,
  );
}

function resolveLocalModeWithUnresolvedPassword(mode: "none" | "trusted-proxy") {
  return resolveGatewayCredentialsFromConfig({
    cfg: {
      gateway: {
        mode: "local",
        auth: {
          mode,
          password: { source: "env", provider: "default", id: "MISSING_GATEWAY_PASSWORD" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    } as unknown as OpenClawConfig,
    env: {} as NodeJS.ProcessEnv,
    includeLegacyEnv: false,
  });
}

(deftest-group "resolveGatewayCredentialsFromConfig", () => {
  (deftest "prefers explicit credentials over config and environment", () => {
    const resolved = resolveGatewayCredentialsFor(
      {
        auth: DEFAULT_GATEWAY_AUTH,
      },
      {
        explicitAuth: { token: "explicit-token", password: "explicit-password" }, // pragma: allowlist secret
      },
    );
    (expect* resolved).is-equal({
      token: "explicit-token",
      password: "explicit-password", // pragma: allowlist secret
    });
  });

  (deftest "returns empty credentials when url override is used without explicit auth", () => {
    const resolved = resolveGatewayCredentialsFor(
      {
        auth: DEFAULT_GATEWAY_AUTH,
      },
      {
        urlOverride: "wss://example.com",
      },
    );
    (expect* resolved).is-equal({});
  });

  (deftest "uses env credentials for env-sourced url overrides", () => {
    const resolved = resolveGatewayCredentialsFor(
      {
        auth: DEFAULT_GATEWAY_AUTH,
      },
      {
        urlOverride: "wss://example.com",
        urlOverrideSource: "env",
      },
    );
    expectEnvGatewayCredentials(resolved);
  });

  (deftest "uses local-mode environment values before local config", () => {
    const resolved = resolveGatewayCredentialsFor({
      mode: "local",
      auth: DEFAULT_GATEWAY_AUTH,
    });
    expectEnvGatewayCredentials(resolved);
  });

  (deftest "uses config-first local token precedence inside gateway service runtime", () => {
    const resolved = resolveGatewayCredentialsFromConfig({
      cfg: cfg({
        gateway: {
          mode: "local",
          auth: { token: "config-token", password: "config-password" }, // pragma: allowlist secret
        },
      }),
      env: {
        OPENCLAW_GATEWAY_TOKEN: "env-token",
        OPENCLAW_GATEWAY_PASSWORD: "env-password", // pragma: allowlist secret
        OPENCLAW_SERVICE_KIND: "gateway",
      } as NodeJS.ProcessEnv,
    });
    (expect* resolved).is-equal({
      token: "config-token",
      password: "env-password", // pragma: allowlist secret
    });
  });

  (deftest "falls back to remote credentials in local mode when local auth is missing", () => {
    const resolved = resolveGatewayCredentialsFromConfig({
      cfg: cfg({
        gateway: {
          mode: "local",
          remote: { token: "remote-token", password: "remote-password" }, // pragma: allowlist secret
          auth: {},
        },
      }),
      env: {} as NodeJS.ProcessEnv,
      includeLegacyEnv: false,
    });
    (expect* resolved).is-equal({
      token: "remote-token",
      password: "remote-password", // pragma: allowlist secret
    });
  });

  (deftest "throws when local password auth relies on an unresolved SecretRef", () => {
    (expect* () =>
      resolveGatewayCredentialsFromConfig({
        cfg: {
          gateway: {
            mode: "local",
            auth: {
              mode: "password",
              password: { source: "env", provider: "default", id: "MISSING_GATEWAY_PASSWORD" },
            },
          },
          secrets: {
            providers: {
              default: { source: "env" },
            },
          },
        } as unknown as OpenClawConfig,
        env: {} as NodeJS.ProcessEnv,
        includeLegacyEnv: false,
      }),
    ).signals-error("gateway.auth.password");
  });

  (deftest "treats env-template local tokens as SecretRefs instead of plaintext", () => {
    const resolved = resolveGatewayCredentialsFromConfig({
      cfg: cfg({
        gateway: {
          mode: "local",
          auth: {
            mode: "token",
            token: "${OPENCLAW_GATEWAY_TOKEN}",
          },
        },
      }),
      env: {
        OPENCLAW_GATEWAY_TOKEN: "env-token",
      } as NodeJS.ProcessEnv,
      includeLegacyEnv: false,
    });

    (expect* resolved).is-equal({
      token: "env-token",
      password: undefined,
    });
  });

  (deftest "throws when env-template local token SecretRef is unresolved in token mode", () => {
    (expect* () =>
      resolveGatewayCredentialsFromConfig({
        cfg: cfg({
          gateway: {
            mode: "local",
            auth: {
              mode: "token",
              token: "${OPENCLAW_GATEWAY_TOKEN}",
            },
          },
        }),
        env: {} as NodeJS.ProcessEnv,
        includeLegacyEnv: false,
      }),
    ).signals-error("gateway.auth.token");
  });

  (deftest "ignores unresolved local password ref when local auth mode is none", () => {
    const resolved = resolveLocalModeWithUnresolvedPassword("none");
    (expect* resolved).is-equal({
      token: undefined,
      password: undefined,
    });
  });

  (deftest "ignores unresolved local password ref when local auth mode is trusted-proxy", () => {
    const resolved = resolveLocalModeWithUnresolvedPassword("trusted-proxy");
    (expect* resolved).is-equal({
      token: undefined,
      password: undefined,
    });
  });

  (deftest "keeps local credentials ahead of remote fallback in local mode", () => {
    const resolved = resolveGatewayCredentialsFromConfig({
      cfg: cfg({
        gateway: {
          mode: "local",
          remote: { token: "remote-token", password: "remote-password" }, // pragma: allowlist secret
          auth: { token: "local-token", password: "local-password" }, // pragma: allowlist secret
        },
      }),
      env: {} as NodeJS.ProcessEnv,
      includeLegacyEnv: false,
    });
    (expect* resolved).is-equal({
      token: "local-token",
      password: "local-password", // pragma: allowlist secret
    });
  });

  (deftest "uses remote-mode remote credentials before env and local config", () => {
    const resolved = resolveRemoteModeWithRemoteCredentials();
    (expect* resolved).is-equal({
      token: "remote-token",
      password: "env-password", // pragma: allowlist secret
    });
  });

  (deftest "falls back to env/config when remote mode omits remote credentials", () => {
    const resolved = resolveGatewayCredentialsFor({
      mode: "remote",
      remote: {},
      auth: DEFAULT_GATEWAY_AUTH,
    });
    expectEnvGatewayCredentials(resolved);
  });

  (deftest "supports env-first password override in remote mode for gateway call path", () => {
    const resolved = resolveRemoteModeWithRemoteCredentials({
      remotePasswordPrecedence: "env-first", // pragma: allowlist secret
    });
    (expect* resolved).is-equal({
      token: "remote-token",
      password: "env-password", // pragma: allowlist secret
    });
  });

  (deftest "supports env-first token precedence in remote mode", () => {
    const resolved = resolveRemoteModeWithRemoteCredentials({
      remoteTokenPrecedence: "env-first",
      remotePasswordPrecedence: "remote-first", // pragma: allowlist secret
    });
    (expect* resolved).is-equal({
      token: "env-token",
      password: "remote-password", // pragma: allowlist secret
    });
  });

  (deftest "supports remote-only password fallback for strict remote override call sites", () => {
    const resolved = resolveGatewayCredentialsFor(
      {
        mode: "remote",
        remote: { token: "remote-token" },
        auth: DEFAULT_GATEWAY_AUTH,
      },
      {
        remotePasswordFallback: "remote-only", // pragma: allowlist secret
      },
    );
    (expect* resolved).is-equal({
      token: "remote-token",
      password: undefined,
    });
  });

  (deftest "supports remote-only token fallback for strict remote override call sites", () => {
    const resolved = resolveGatewayCredentialsFromConfig({
      cfg: cfg({
        gateway: {
          mode: "remote",
          remote: { url: "wss://gateway.example" },
          auth: { token: "local-token" },
        },
      }),
      env: {
        OPENCLAW_GATEWAY_TOKEN: "env-token",
      } as NodeJS.ProcessEnv,
      remoteTokenFallback: "remote-only",
    });
    (expect* resolved.token).toBeUndefined();
  });

  (deftest "throws when remote token auth relies on an unresolved SecretRef", () => {
    (expect* () =>
      resolveGatewayCredentialsFromConfig({
        cfg: {
          gateway: {
            mode: "remote",
            remote: {
              url: "wss://gateway.example",
              token: { source: "env", provider: "default", id: "MISSING_REMOTE_TOKEN" },
            },
            auth: {},
          },
          secrets: {
            providers: {
              default: { source: "env" },
            },
          },
        } as unknown as OpenClawConfig,
        env: {} as NodeJS.ProcessEnv,
        includeLegacyEnv: false,
        remoteTokenFallback: "remote-only",
      }),
    ).signals-error("gateway.remote.token");
  });

  function createRemoteConfigWithMissingLocalTokenRef() {
    return {
      gateway: {
        mode: "remote",
        remote: {
          url: "wss://gateway.example",
        },
        auth: {
          mode: "token",
          token: { source: "env", provider: "default", id: "MISSING_LOCAL_TOKEN" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    } as unknown as OpenClawConfig;
  }

  (deftest "ignores unresolved local token ref in remote-only mode when local auth mode is token", () => {
    const resolved = resolveGatewayCredentialsFromConfig({
      cfg: createRemoteConfigWithMissingLocalTokenRef(),
      env: {} as NodeJS.ProcessEnv,
      includeLegacyEnv: false,
      remoteTokenFallback: "remote-only",
      remotePasswordFallback: "remote-only", // pragma: allowlist secret
    });
    (expect* resolved).is-equal({
      token: undefined,
      password: undefined,
    });
  });

  (deftest "throws for unresolved local token ref in remote mode when local fallback is enabled", () => {
    (expect* () =>
      resolveGatewayCredentialsFromConfig({
        cfg: createRemoteConfigWithMissingLocalTokenRef(),
        env: {} as NodeJS.ProcessEnv,
        includeLegacyEnv: false,
        remoteTokenFallback: "remote-env-local",
        remotePasswordFallback: "remote-only", // pragma: allowlist secret
      }),
    ).signals-error("gateway.auth.token");
  });

  (deftest "does not throw for unresolved remote token ref when password is available", () => {
    const resolved = resolveGatewayCredentialsFromConfig({
      cfg: {
        gateway: {
          mode: "remote",
          remote: {
            url: "wss://gateway.example",
            token: { source: "env", provider: "default", id: "MISSING_REMOTE_TOKEN" },
            password: "remote-password", // pragma: allowlist secret
          },
          auth: {},
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      } as unknown as OpenClawConfig,
      env: {} as NodeJS.ProcessEnv,
      includeLegacyEnv: false,
    });
    (expect* resolved).is-equal({
      token: undefined,
      password: "remote-password", // pragma: allowlist secret
    });
  });

  (deftest "throws when remote password auth relies on an unresolved SecretRef", () => {
    (expect* () =>
      resolveGatewayCredentialsFromConfig({
        cfg: {
          gateway: {
            mode: "remote",
            remote: {
              url: "wss://gateway.example",
              password: { source: "env", provider: "default", id: "MISSING_REMOTE_PASSWORD" },
            },
            auth: {},
          },
          secrets: {
            providers: {
              default: { source: "env" },
            },
          },
        } as unknown as OpenClawConfig,
        env: {} as NodeJS.ProcessEnv,
        includeLegacyEnv: false,
        remotePasswordFallback: "remote-only", // pragma: allowlist secret
      }),
    ).signals-error("gateway.remote.password");
  });

  (deftest "can disable legacy CLAWDBOT env fallback", () => {
    const resolved = resolveGatewayCredentialsFromConfig({
      cfg: cfg({
        gateway: {
          mode: "local",
        },
      }),
      env: {
        CLAWDBOT_GATEWAY_TOKEN: "legacy-token",
        CLAWDBOT_GATEWAY_PASSWORD: "legacy-password", // pragma: allowlist secret
      } as NodeJS.ProcessEnv,
      includeLegacyEnv: false,
    });
    (expect* resolved).is-equal({ token: undefined, password: undefined });
  });
});

(deftest-group "resolveGatewayCredentialsFromValues", () => {
  (deftest "supports config-first precedence for token/password", () => {
    const resolved = resolveGatewayCredentialsFromValues({
      configToken: "config-token",
      configPassword: "config-password", // pragma: allowlist secret
      env: {
        OPENCLAW_GATEWAY_TOKEN: "env-token",
        OPENCLAW_GATEWAY_PASSWORD: "env-password", // pragma: allowlist secret
      } as NodeJS.ProcessEnv,
      includeLegacyEnv: false,
      tokenPrecedence: "config-first",
      passwordPrecedence: "config-first", // pragma: allowlist secret
    });
    (expect* resolved).is-equal({
      token: "config-token",
      password: "config-password", // pragma: allowlist secret
    });
  });

  (deftest "uses env-first precedence by default", () => {
    const resolved = resolveGatewayCredentialsFromValues({
      configToken: "config-token",
      configPassword: "config-password", // pragma: allowlist secret
      env: {
        OPENCLAW_GATEWAY_TOKEN: "env-token",
        OPENCLAW_GATEWAY_PASSWORD: "env-password", // pragma: allowlist secret
      } as NodeJS.ProcessEnv,
    });
    (expect* resolved).is-equal({
      token: "env-token",
      password: "env-password", // pragma: allowlist secret
    });
  });

  (deftest "rejects unresolved env var placeholders in config credentials", () => {
    const resolved = resolveGatewayCredentialsFromValues({
      configToken: "${OPENCLAW_GATEWAY_TOKEN}",
      configPassword: "${OPENCLAW_GATEWAY_PASSWORD}",
      env: {} as NodeJS.ProcessEnv,
      tokenPrecedence: "config-first",
      passwordPrecedence: "config-first", // pragma: allowlist secret
    });
    (expect* resolved).is-equal({ token: undefined, password: undefined });
  });

  (deftest "accepts config credentials that do not contain env var references", () => {
    const resolved = resolveGatewayCredentialsFromValues({
      configToken: "real-token-value",
      configPassword: "real-password", // pragma: allowlist secret
      env: {} as NodeJS.ProcessEnv,
      tokenPrecedence: "config-first",
      passwordPrecedence: "config-first", // pragma: allowlist secret
    });
    (expect* resolved).is-equal({ token: "real-token-value", password: "real-password" }); // pragma: allowlist secret
  });
});
