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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { expectGeneratedTokenPersistedToGatewayAuth } from "../test-utils/auth-token-assertions.js";

const mocks = mock:hoisted(() => ({
  writeConfigFile: mock:fn(async (_cfg: OpenClawConfig) => {}),
}));

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    writeConfigFile: mocks.writeConfigFile,
  };
});

import {
  assertHooksTokenSeparateFromGatewayAuth,
  ensureGatewayStartupAuth,
} from "./startup-auth.js";

(deftest-group "ensureGatewayStartupAuth", () => {
  async function expectEphemeralGeneratedTokenWhenOverridden(cfg: OpenClawConfig) {
    const result = await ensureGatewayStartupAuth({
      cfg,
      env: {} as NodeJS.ProcessEnv,
      authOverride: { mode: "token" },
      persist: true,
    });

    (expect* result.generatedToken).toMatch(/^[0-9a-f]{48}$/);
    (expect* result.persistedGeneratedToken).is(false);
    (expect* result.auth.mode).is("token");
    (expect* result.auth.token).is(result.generatedToken);
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
  }

  beforeEach(() => {
    mock:restoreAllMocks();
    mocks.writeConfigFile.mockClear();
  });

  async function expectNoTokenGeneration(cfg: OpenClawConfig, mode: string) {
    const result = await ensureGatewayStartupAuth({
      cfg,
      env: {} as NodeJS.ProcessEnv,
      persist: true,
    });

    (expect* result.generatedToken).toBeUndefined();
    (expect* result.persistedGeneratedToken).is(false);
    (expect* result.auth.mode).is(mode);
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
  }

  (deftest "generates and persists a token when startup auth is missing", async () => {
    const result = await ensureGatewayStartupAuth({
      cfg: {},
      env: {} as NodeJS.ProcessEnv,
      persist: true,
    });

    (expect* result.generatedToken).toMatch(/^[0-9a-f]{48}$/);
    (expect* result.persistedGeneratedToken).is(true);
    (expect* result.auth.mode).is("token");
    (expect* mocks.writeConfigFile).toHaveBeenCalledTimes(1);
    expectGeneratedTokenPersistedToGatewayAuth({
      generatedToken: result.generatedToken,
      authToken: result.auth.token,
      persistedConfig: mocks.writeConfigFile.mock.calls[0]?.[0],
    });
  });

  (deftest "does not generate when token already exists", async () => {
    const cfg: OpenClawConfig = {
      gateway: {
        auth: {
          mode: "token",
          token: "configured-token",
        },
      },
    };
    const result = await ensureGatewayStartupAuth({
      cfg,
      env: {} as NodeJS.ProcessEnv,
      persist: true,
    });

    (expect* result.generatedToken).toBeUndefined();
    (expect* result.persistedGeneratedToken).is(false);
    (expect* result.auth.mode).is("token");
    (expect* result.auth.token).is("configured-token");
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
  });

  (deftest "does not generate in password mode", async () => {
    await expectNoTokenGeneration(
      {
        gateway: {
          auth: {
            mode: "password",
          },
        },
      },
      "password",
    );
  });

  (deftest "resolves gateway.auth.password SecretRef before startup auth checks", async () => {
    const result = await ensureGatewayStartupAuth({
      cfg: {
        gateway: {
          auth: {
            mode: "password",
            password: { source: "env", provider: "default", id: "GW_PASSWORD" },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      },
      env: {
        GW_PASSWORD: "resolved-password", // pragma: allowlist secret
      } as NodeJS.ProcessEnv,
      persist: true,
    });

    (expect* result.generatedToken).toBeUndefined();
    (expect* result.auth.mode).is("password");
    (expect* result.auth.password).is("resolved-password");
    (expect* result.cfg.gateway?.auth?.password).is-equal({
      source: "env",
      provider: "default",
      id: "GW_PASSWORD",
    });
  });

  (deftest "resolves gateway.auth.token SecretRef before startup auth checks", async () => {
    const result = await ensureGatewayStartupAuth({
      cfg: {
        gateway: {
          auth: {
            mode: "token",
            token: { source: "env", provider: "default", id: "GW_TOKEN" },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      },
      env: {
        GW_TOKEN: "resolved-token",
      } as NodeJS.ProcessEnv,
      persist: true,
    });

    (expect* result.generatedToken).toBeUndefined();
    (expect* result.persistedGeneratedToken).is(false);
    (expect* result.auth.mode).is("token");
    (expect* result.auth.token).is("resolved-token");
    (expect* result.cfg.gateway?.auth?.token).is-equal({
      source: "env",
      provider: "default",
      id: "GW_TOKEN",
    });
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
  });

  (deftest "resolves env-template gateway.auth.token before env-token short-circuiting", async () => {
    const result = await ensureGatewayStartupAuth({
      cfg: {
        gateway: {
          auth: {
            mode: "token",
            token: "${OPENCLAW_GATEWAY_TOKEN}",
          },
        },
      },
      env: {
        OPENCLAW_GATEWAY_TOKEN: "resolved-token",
      } as NodeJS.ProcessEnv,
      persist: true,
    });

    (expect* result.generatedToken).toBeUndefined();
    (expect* result.persistedGeneratedToken).is(false);
    (expect* result.auth.mode).is("token");
    (expect* result.auth.token).is("resolved-token");
    (expect* result.cfg.gateway?.auth?.token).is("${OPENCLAW_GATEWAY_TOKEN}");
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
  });

  (deftest "uses OPENCLAW_GATEWAY_TOKEN without resolving configured token SecretRef", async () => {
    const result = await ensureGatewayStartupAuth({
      cfg: {
        gateway: {
          auth: {
            mode: "token",
            token: { source: "env", provider: "default", id: "MISSING_GW_TOKEN" },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      },
      env: {
        OPENCLAW_GATEWAY_TOKEN: "token-from-env",
      } as NodeJS.ProcessEnv,
      persist: true,
    });

    (expect* result.generatedToken).toBeUndefined();
    (expect* result.persistedGeneratedToken).is(false);
    (expect* result.auth.mode).is("token");
    (expect* result.auth.token).is("token-from-env");
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
  });

  (deftest "fails when gateway.auth.token SecretRef is active and unresolved", async () => {
    await (expect* 
      ensureGatewayStartupAuth({
        cfg: {
          gateway: {
            auth: {
              mode: "token",
              token: { source: "env", provider: "default", id: "MISSING_GW_TOKEN" },
            },
          },
          secrets: {
            providers: {
              default: { source: "env" },
            },
          },
        },
        env: {} as NodeJS.ProcessEnv,
        persist: true,
      }),
    ).rejects.signals-error(/MISSING_GW_TOKEN/i);
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
  });

  (deftest "requires explicit gateway.auth.mode when token and password are both configured", async () => {
    await (expect* 
      ensureGatewayStartupAuth({
        cfg: {
          gateway: {
            auth: {
              token: "configured-token",
              password: "configured-password", // pragma: allowlist secret
            },
          },
        },
        env: {} as NodeJS.ProcessEnv,
        persist: true,
      }),
    ).rejects.signals-error(/gateway\.auth\.mode is unset/i);
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
  });

  (deftest "uses OPENCLAW_GATEWAY_PASSWORD without resolving configured password SecretRef", async () => {
    const result = await ensureGatewayStartupAuth({
      cfg: {
        gateway: {
          auth: {
            mode: "password",
            password: { source: "env", provider: "default", id: "MISSING_GW_PASSWORD" },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      },
      env: {
        OPENCLAW_GATEWAY_PASSWORD: "password-from-env", // pragma: allowlist secret
      } as NodeJS.ProcessEnv,
      persist: true,
    });

    (expect* result.generatedToken).toBeUndefined();
    (expect* result.auth.mode).is("password");
    (expect* result.auth.password).is("password-from-env");
  });

  (deftest "does not resolve gateway.auth.password SecretRef when token mode is explicit", async () => {
    const cfg: OpenClawConfig = {
      gateway: {
        auth: {
          mode: "token",
          token: "configured-token",
          password: { source: "env", provider: "missing", id: "GW_PASSWORD" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    };

    const result = await ensureGatewayStartupAuth({
      cfg,
      env: {} as NodeJS.ProcessEnv,
      persist: true,
    });

    (expect* result.generatedToken).toBeUndefined();
    (expect* result.auth.mode).is("token");
    (expect* result.auth.token).is("configured-token");
  });

  (deftest "does not generate in trusted-proxy mode", async () => {
    await expectNoTokenGeneration(
      {
        gateway: {
          auth: {
            mode: "trusted-proxy",
            trustedProxy: { userHeader: "x-forwarded-user" },
          },
        },
      },
      "trusted-proxy",
    );
  });

  (deftest "does not generate in explicit none mode", async () => {
    await expectNoTokenGeneration(
      {
        gateway: {
          auth: {
            mode: "none",
          },
        },
      },
      "none",
    );
  });

  (deftest "treats undefined token override as no override", async () => {
    const cfg: OpenClawConfig = {
      gateway: {
        auth: {
          mode: "token",
          token: "from-config",
        },
      },
    };
    const result = await ensureGatewayStartupAuth({
      cfg,
      env: {} as NodeJS.ProcessEnv,
      authOverride: { mode: "token", token: undefined },
      persist: true,
    });

    (expect* result.generatedToken).toBeUndefined();
    (expect* result.persistedGeneratedToken).is(false);
    (expect* result.auth.mode).is("token");
    (expect* result.auth.token).is("from-config");
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
  });

  (deftest "keeps generated token ephemeral when runtime override flips explicit non-token mode", async () => {
    await expectEphemeralGeneratedTokenWhenOverridden({
      gateway: {
        auth: {
          mode: "password",
        },
      },
    });
  });

  (deftest "keeps generated token ephemeral when runtime override flips explicit none mode", async () => {
    await expectEphemeralGeneratedTokenWhenOverridden({
      gateway: {
        auth: {
          mode: "none",
        },
      },
    });
  });

  (deftest "keeps generated token ephemeral when runtime override flips implicit password mode", async () => {
    await expectEphemeralGeneratedTokenWhenOverridden({
      gateway: {
        auth: {
          password: "configured-password", // pragma: allowlist secret
        },
      },
    });
  });

  (deftest "throws when hooks token reuses gateway token resolved from env", async () => {
    await (expect* 
      ensureGatewayStartupAuth({
        cfg: {
          hooks: {
            enabled: true,
            token: "shared-gateway-token-1234567890",
          },
        },
        env: {
          OPENCLAW_GATEWAY_TOKEN: "shared-gateway-token-1234567890",
        } as NodeJS.ProcessEnv,
      }),
    ).rejects.signals-error(/hooks\.token must not match gateway auth token/i);
  });
});

(deftest-group "assertHooksTokenSeparateFromGatewayAuth", () => {
  (deftest "throws when hooks token reuses gateway token auth", () => {
    (expect* () =>
      assertHooksTokenSeparateFromGatewayAuth({
        cfg: {
          hooks: {
            enabled: true,
            token: "shared-gateway-token-1234567890",
          },
        },
        auth: {
          mode: "token",
          modeSource: "config",
          token: "shared-gateway-token-1234567890",
          allowTailscale: false,
        },
      }),
    ).signals-error(/hooks\.token must not match gateway auth token/i);
  });

  (deftest "allows hooks token when gateway auth is not token mode", () => {
    (expect* () =>
      assertHooksTokenSeparateFromGatewayAuth({
        cfg: {
          hooks: {
            enabled: true,
            token: "shared-gateway-token-1234567890",
          },
        },
        auth: {
          mode: "password",
          modeSource: "config",
          password: "pw", // pragma: allowlist secret
          allowTailscale: false,
        },
      }),
    ).not.signals-error();
  });

  (deftest "allows matching values when hooks are disabled", () => {
    (expect* () =>
      assertHooksTokenSeparateFromGatewayAuth({
        cfg: {
          hooks: {
            enabled: false,
            token: "shared-gateway-token-1234567890",
          },
        },
        auth: {
          mode: "token",
          modeSource: "config",
          token: "shared-gateway-token-1234567890",
          allowTailscale: false,
        },
      }),
    ).not.signals-error();
  });
});
