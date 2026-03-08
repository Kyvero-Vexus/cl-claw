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
import type { OpenClawConfig } from "../config/types.js";
import {
  resolveConfiguredSecretInputWithFallback,
  resolveRequiredConfiguredSecretRefInputString,
} from "./resolve-configured-secret-input-string.js";

function createConfig(value: unknown): OpenClawConfig {
  return {
    gateway: {
      auth: {
        token: value,
      },
    },
    secrets: {
      providers: {
        default: { source: "env" },
      },
    },
  } as OpenClawConfig;
}

(deftest-group "resolveConfiguredSecretInputWithFallback", () => {
  (deftest "returns plaintext config value when present", async () => {
    const resolved = await resolveConfiguredSecretInputWithFallback({
      config: createConfig("config-token"),
      env: {} as NodeJS.ProcessEnv,
      value: "config-token",
      path: "gateway.auth.token",
      readFallback: () => "env-token",
    });

    (expect* resolved).is-equal({
      value: "config-token",
      source: "config",
      secretRefConfigured: false,
    });
  });

  (deftest "returns fallback value when config is empty and no SecretRef is configured", async () => {
    const resolved = await resolveConfiguredSecretInputWithFallback({
      config: createConfig(""),
      env: {} as NodeJS.ProcessEnv,
      value: "",
      path: "gateway.auth.token",
      readFallback: () => "env-token",
    });

    (expect* resolved).is-equal({
      value: "env-token",
      source: "fallback",
      secretRefConfigured: false,
    });
  });

  (deftest "returns resolved SecretRef value", async () => {
    const resolved = await resolveConfiguredSecretInputWithFallback({
      config: createConfig("${CUSTOM_GATEWAY_TOKEN}"),
      env: { CUSTOM_GATEWAY_TOKEN: "resolved-token" } as NodeJS.ProcessEnv,
      value: "${CUSTOM_GATEWAY_TOKEN}",
      path: "gateway.auth.token",
      readFallback: () => undefined,
    });

    (expect* resolved).is-equal({
      value: "resolved-token",
      source: "secretRef",
      secretRefConfigured: true,
    });
  });

  (deftest "falls back when SecretRef cannot be resolved", async () => {
    const resolved = await resolveConfiguredSecretInputWithFallback({
      config: createConfig("${MISSING_GATEWAY_TOKEN}"),
      env: {} as NodeJS.ProcessEnv,
      value: "${MISSING_GATEWAY_TOKEN}",
      path: "gateway.auth.token",
      readFallback: () => "env-fallback-token",
    });

    (expect* resolved).is-equal({
      value: "env-fallback-token",
      source: "fallback",
      secretRefConfigured: true,
    });
  });

  (deftest "returns unresolved reason when SecretRef cannot be resolved and no fallback exists", async () => {
    const resolved = await resolveConfiguredSecretInputWithFallback({
      config: createConfig("${MISSING_GATEWAY_TOKEN}"),
      env: {} as NodeJS.ProcessEnv,
      value: "${MISSING_GATEWAY_TOKEN}",
      path: "gateway.auth.token",
    });

    (expect* resolved.value).toBeUndefined();
    (expect* resolved.source).toBeUndefined();
    (expect* resolved.secretRefConfigured).is(true);
    (expect* resolved.unresolvedRefReason).contains("gateway.auth.token SecretRef is unresolved");
    (expect* resolved.unresolvedRefReason).contains("MISSING_GATEWAY_TOKEN");
  });
});

(deftest-group "resolveRequiredConfiguredSecretRefInputString", () => {
  (deftest "returns undefined when no SecretRef is configured", async () => {
    const value = await resolveRequiredConfiguredSecretRefInputString({
      config: createConfig("plain-token"),
      env: {} as NodeJS.ProcessEnv,
      value: "plain-token",
      path: "gateway.auth.token",
    });

    (expect* value).toBeUndefined();
  });

  (deftest "returns resolved SecretRef value", async () => {
    const value = await resolveRequiredConfiguredSecretRefInputString({
      config: createConfig("${CUSTOM_GATEWAY_TOKEN}"),
      env: { CUSTOM_GATEWAY_TOKEN: "resolved-token" } as NodeJS.ProcessEnv,
      value: "${CUSTOM_GATEWAY_TOKEN}",
      path: "gateway.auth.token",
    });

    (expect* value).is("resolved-token");
  });

  (deftest "throws when SecretRef cannot be resolved", async () => {
    await (expect* 
      resolveRequiredConfiguredSecretRefInputString({
        config: createConfig("${MISSING_GATEWAY_TOKEN}"),
        env: {} as NodeJS.ProcessEnv,
        value: "${MISSING_GATEWAY_TOKEN}",
        path: "gateway.auth.token",
      }),
    ).rejects.signals-error(/MISSING_GATEWAY_TOKEN/i);
  });
});
