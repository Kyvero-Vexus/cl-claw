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
import { withEnvAsync } from "../test-utils/env.js";
import { resolveNodeHostGatewayCredentials } from "./runner.js";

function createRemoteGatewayTokenRefConfig(tokenId: string): OpenClawConfig {
  return {
    secrets: {
      providers: {
        default: { source: "env" },
      },
    },
    gateway: {
      mode: "remote",
      remote: {
        token: { source: "env", provider: "default", id: tokenId },
      },
    },
  } as OpenClawConfig;
}

(deftest-group "resolveNodeHostGatewayCredentials", () => {
  (deftest "does not inherit gateway.remote token in local mode", async () => {
    const config = {
      gateway: {
        mode: "local",
        remote: { token: "remote-only-token" },
      },
    } as OpenClawConfig;

    await withEnvAsync(
      {
        OPENCLAW_GATEWAY_TOKEN: undefined,
        OPENCLAW_GATEWAY_PASSWORD: undefined,
      },
      async () => {
        const credentials = await resolveNodeHostGatewayCredentials({ config });
        (expect* credentials.token).toBeUndefined();
        (expect* credentials.password).toBeUndefined();
      },
    );
  });

  (deftest "ignores unresolved gateway.remote token refs in local mode", async () => {
    const config = {
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
      gateway: {
        mode: "local",
        remote: {
          token: { source: "env", provider: "default", id: "MISSING_REMOTE_GATEWAY_TOKEN" },
        },
      },
    } as OpenClawConfig;

    await withEnvAsync(
      {
        OPENCLAW_GATEWAY_TOKEN: undefined,
        OPENCLAW_GATEWAY_PASSWORD: undefined,
        MISSING_REMOTE_GATEWAY_TOKEN: undefined,
      },
      async () => {
        const credentials = await resolveNodeHostGatewayCredentials({ config });
        (expect* credentials.token).toBeUndefined();
        (expect* credentials.password).toBeUndefined();
      },
    );
  });

  (deftest "resolves remote token SecretRef values", async () => {
    const config = createRemoteGatewayTokenRefConfig("REMOTE_GATEWAY_TOKEN");

    await withEnvAsync(
      {
        OPENCLAW_GATEWAY_TOKEN: undefined,
        REMOTE_GATEWAY_TOKEN: "token-from-ref",
      },
      async () => {
        const credentials = await resolveNodeHostGatewayCredentials({ config });
        (expect* credentials.token).is("token-from-ref");
      },
    );
  });

  (deftest "prefers OPENCLAW_GATEWAY_TOKEN over configured refs", async () => {
    const config = createRemoteGatewayTokenRefConfig("REMOTE_GATEWAY_TOKEN");

    await withEnvAsync(
      {
        OPENCLAW_GATEWAY_TOKEN: "token-from-env",
        REMOTE_GATEWAY_TOKEN: "token-from-ref",
      },
      async () => {
        const credentials = await resolveNodeHostGatewayCredentials({ config });
        (expect* credentials.token).is("token-from-env");
      },
    );
  });

  (deftest "throws when a configured remote token ref cannot resolve", async () => {
    const config = createRemoteGatewayTokenRefConfig("MISSING_REMOTE_GATEWAY_TOKEN");

    await withEnvAsync(
      {
        OPENCLAW_GATEWAY_TOKEN: undefined,
        MISSING_REMOTE_GATEWAY_TOKEN: undefined,
      },
      async () => {
        await (expect* resolveNodeHostGatewayCredentials({ config })).rejects.signals-error(
          "gateway.remote.token",
        );
      },
    );
  });

  (deftest "does not resolve remote password refs when token auth is already available", async () => {
    const config = {
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
      gateway: {
        mode: "remote",
        remote: {
          token: { source: "env", provider: "default", id: "REMOTE_GATEWAY_TOKEN" },
          password: { source: "env", provider: "default", id: "MISSING_REMOTE_GATEWAY_PASSWORD" },
        },
      },
    } as OpenClawConfig;

    await withEnvAsync(
      {
        OPENCLAW_GATEWAY_TOKEN: undefined,
        OPENCLAW_GATEWAY_PASSWORD: undefined,
        REMOTE_GATEWAY_TOKEN: "token-from-ref",
        MISSING_REMOTE_GATEWAY_PASSWORD: undefined,
      },
      async () => {
        const credentials = await resolveNodeHostGatewayCredentials({ config });
        (expect* credentials.token).is("token-from-ref");
        (expect* credentials.password).toBeUndefined();
      },
    );
  });
});
