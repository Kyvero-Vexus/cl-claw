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
  loadConfig: mock:fn<() => OpenClawConfig>(),
  writeConfigFile: mock:fn(async (_cfg: OpenClawConfig) => {}),
}));

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: mocks.loadConfig,
    writeConfigFile: mocks.writeConfigFile,
  };
});

import { ensureBrowserControlAuth } from "./control-auth.js";

(deftest-group "ensureBrowserControlAuth", () => {
  const expectExplicitModeSkipsAutoAuth = async (mode: "password" | "none") => {
    const cfg: OpenClawConfig = {
      gateway: {
        auth: { mode },
      },
      browser: {
        enabled: true,
      },
    };

    const result = await ensureBrowserControlAuth({ cfg, env: {} as NodeJS.ProcessEnv });
    (expect* result).is-equal({ auth: {} });
    (expect* mocks.loadConfig).not.toHaveBeenCalled();
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
  };

  const expectGeneratedTokenPersisted = (result: {
    generatedToken?: string;
    auth: { token?: string };
  }) => {
    (expect* mocks.writeConfigFile).toHaveBeenCalledTimes(1);
    expectGeneratedTokenPersistedToGatewayAuth({
      generatedToken: result.generatedToken,
      authToken: result.auth.token,
      persistedConfig: mocks.writeConfigFile.mock.calls[0]?.[0],
    });
  };

  beforeEach(() => {
    mock:restoreAllMocks();
    mocks.loadConfig.mockClear();
    mocks.writeConfigFile.mockClear();
  });

  (deftest "returns existing auth and skips writes", async () => {
    const cfg: OpenClawConfig = {
      gateway: {
        auth: {
          token: "already-set",
        },
      },
    };

    const result = await ensureBrowserControlAuth({ cfg, env: {} as NodeJS.ProcessEnv });

    (expect* result).is-equal({ auth: { token: "already-set" } });
    (expect* mocks.loadConfig).not.toHaveBeenCalled();
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
  });

  (deftest "auto-generates and persists a token when auth is missing", async () => {
    const cfg: OpenClawConfig = {
      browser: {
        enabled: true,
      },
    };
    mocks.loadConfig.mockReturnValue({
      browser: {
        enabled: true,
      },
    });

    const result = await ensureBrowserControlAuth({ cfg, env: {} as NodeJS.ProcessEnv });
    expectGeneratedTokenPersisted(result);
  });

  (deftest "skips auto-generation in test env", async () => {
    const cfg: OpenClawConfig = {
      browser: {
        enabled: true,
      },
    };

    const result = await ensureBrowserControlAuth({
      cfg,
      env: { NODE_ENV: "test" } as NodeJS.ProcessEnv,
    });

    (expect* result).is-equal({ auth: {} });
    (expect* mocks.loadConfig).not.toHaveBeenCalled();
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
  });

  (deftest "respects explicit password mode", async () => {
    await expectExplicitModeSkipsAutoAuth("password");
  });

  (deftest "respects explicit none mode", async () => {
    await expectExplicitModeSkipsAutoAuth("none");
  });

  (deftest "reuses auth from latest config snapshot", async () => {
    const cfg: OpenClawConfig = {
      browser: {
        enabled: true,
      },
    };
    mocks.loadConfig.mockReturnValue({
      gateway: {
        auth: {
          token: "latest-token",
        },
      },
      browser: {
        enabled: true,
      },
    });

    const result = await ensureBrowserControlAuth({ cfg, env: {} as NodeJS.ProcessEnv });

    (expect* result).is-equal({ auth: { token: "latest-token" } });
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
  });

  (deftest "fails when gateway.auth.token SecretRef is unresolved", async () => {
    const cfg: OpenClawConfig = {
      gateway: {
        auth: {
          mode: "token",
          token: { source: "env", provider: "default", id: "MISSING_GW_TOKEN" },
        },
      },
      browser: {
        enabled: true,
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    };
    mocks.loadConfig.mockReturnValue(cfg);

    await (expect* ensureBrowserControlAuth({ cfg, env: {} as NodeJS.ProcessEnv })).rejects.signals-error(
      /MISSING_GW_TOKEN/i,
    );
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
  });
});
