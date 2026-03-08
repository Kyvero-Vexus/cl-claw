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

const readConfigFileSnapshotMock = mock:hoisted(() => mock:fn());
const writeConfigFileMock = mock:hoisted(() => mock:fn());
const resolveSecretInputRefMock = mock:hoisted(() =>
  mock:fn((): { ref: unknown } => ({ ref: undefined })),
);
const hasConfiguredSecretInputMock = mock:hoisted(() =>
  mock:fn((value: unknown) => {
    if (typeof value === "string") {
      return value.trim().length > 0;
    }
    return value != null;
  }),
);
const resolveGatewayAuthMock = mock:hoisted(() =>
  mock:fn(() => ({
    mode: "token",
    token: undefined,
    password: undefined,
    allowTailscale: false,
  })),
);
const shouldRequireGatewayTokenForInstallMock = mock:hoisted(() => mock:fn(() => true));
const resolveSecretRefValuesMock = mock:hoisted(() => mock:fn());
const secretRefKeyMock = mock:hoisted(() => mock:fn(() => "env:default:OPENCLAW_GATEWAY_TOKEN"));
const randomTokenMock = mock:hoisted(() => mock:fn(() => "generated-token"));

mock:mock("../config/config.js", () => ({
  readConfigFileSnapshot: readConfigFileSnapshotMock,
  writeConfigFile: writeConfigFileMock,
}));

mock:mock("../config/types.secrets.js", () => ({
  resolveSecretInputRef: resolveSecretInputRefMock,
  hasConfiguredSecretInput: hasConfiguredSecretInputMock,
}));

mock:mock("../gateway/auth.js", () => ({
  resolveGatewayAuth: resolveGatewayAuthMock,
}));

mock:mock("../gateway/auth-install-policy.js", () => ({
  shouldRequireGatewayTokenForInstall: shouldRequireGatewayTokenForInstallMock,
}));

mock:mock("../secrets/ref-contract.js", () => ({
  secretRefKey: secretRefKeyMock,
}));

mock:mock("../secrets/resolve.js", () => ({
  resolveSecretRefValues: resolveSecretRefValuesMock,
}));

mock:mock("./onboard-helpers.js", () => ({
  randomToken: randomTokenMock,
}));

const { resolveGatewayInstallToken } = await import("./gateway-install-token.js");

(deftest-group "resolveGatewayInstallToken", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    readConfigFileSnapshotMock.mockResolvedValue({ exists: false, valid: true, config: {} });
    resolveSecretInputRefMock.mockReturnValue({ ref: undefined });
    hasConfiguredSecretInputMock.mockImplementation((value: unknown) => {
      if (typeof value === "string") {
        return value.trim().length > 0;
      }
      return value != null;
    });
    resolveSecretRefValuesMock.mockResolvedValue(new Map());
    shouldRequireGatewayTokenForInstallMock.mockReturnValue(true);
    resolveGatewayAuthMock.mockReturnValue({
      mode: "token",
      token: undefined,
      password: undefined,
      allowTailscale: false,
    });
    randomTokenMock.mockReturnValue("generated-token");
  });

  (deftest "uses plaintext gateway.auth.token when configured", async () => {
    const result = await resolveGatewayInstallToken({
      config: {
        gateway: { auth: { token: "config-token" } },
      } as OpenClawConfig,
      env: {} as NodeJS.ProcessEnv,
    });

    (expect* result).is-equal({
      token: "config-token",
      tokenRefConfigured: false,
      unavailableReason: undefined,
      warnings: [],
    });
  });

  (deftest "validates SecretRef token but does not persist resolved plaintext", async () => {
    const tokenRef = { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_TOKEN" };
    resolveSecretInputRefMock.mockReturnValue({ ref: tokenRef });
    resolveSecretRefValuesMock.mockResolvedValue(
      new Map([["env:default:OPENCLAW_GATEWAY_TOKEN", "resolved-token"]]),
    );

    const result = await resolveGatewayInstallToken({
      config: {
        gateway: { auth: { mode: "token", token: tokenRef } },
      } as OpenClawConfig,
      env: { OPENCLAW_GATEWAY_TOKEN: "resolved-token" } as NodeJS.ProcessEnv,
    });

    (expect* result.token).toBeUndefined();
    (expect* result.tokenRefConfigured).is(true);
    (expect* result.unavailableReason).toBeUndefined();
    (expect* result.warnings.some((message) => message.includes("SecretRef-managed"))).is-truthy();
  });

  (deftest "returns unavailable reason when token SecretRef is unresolved in token mode", async () => {
    resolveSecretInputRefMock.mockReturnValue({
      ref: { source: "env", provider: "default", id: "MISSING_GATEWAY_TOKEN" },
    });
    resolveSecretRefValuesMock.mockRejectedValue(new Error("missing env var"));

    const result = await resolveGatewayInstallToken({
      config: {
        gateway: { auth: { mode: "token", token: "${MISSING_GATEWAY_TOKEN}" } },
      } as OpenClawConfig,
      env: {} as NodeJS.ProcessEnv,
    });

    (expect* result.token).toBeUndefined();
    (expect* result.unavailableReason).contains("gateway.auth.token SecretRef is configured");
  });

  (deftest "returns unavailable reason when token and password are both configured and mode is unset", async () => {
    const result = await resolveGatewayInstallToken({
      config: {
        gateway: {
          auth: {
            token: "token-value",
            password: "password-value", // pragma: allowlist secret
          },
        },
      } as OpenClawConfig,
      env: {} as NodeJS.ProcessEnv,
      autoGenerateWhenMissing: true,
      persistGeneratedToken: true,
    });

    (expect* result.token).toBeUndefined();
    (expect* result.unavailableReason).contains("gateway.auth.mode is unset");
    (expect* result.unavailableReason).contains("openclaw config set gateway.auth.mode token");
    (expect* result.unavailableReason).contains("openclaw config set gateway.auth.mode password");
    (expect* writeConfigFileMock).not.toHaveBeenCalled();
    (expect* resolveSecretRefValuesMock).not.toHaveBeenCalled();
  });

  (deftest "auto-generates token when no source exists and auto-generation is enabled", async () => {
    const result = await resolveGatewayInstallToken({
      config: {
        gateway: { auth: { mode: "token" } },
      } as OpenClawConfig,
      env: {} as NodeJS.ProcessEnv,
      autoGenerateWhenMissing: true,
    });

    (expect* result.token).is("generated-token");
    (expect* result.unavailableReason).toBeUndefined();
    (expect* 
      result.warnings.some((message) => message.includes("without saving to config")),
    ).is-truthy();
    (expect* writeConfigFileMock).not.toHaveBeenCalled();
  });

  (deftest "persists auto-generated token when requested", async () => {
    const result = await resolveGatewayInstallToken({
      config: {
        gateway: { auth: { mode: "token" } },
      } as OpenClawConfig,
      env: {} as NodeJS.ProcessEnv,
      autoGenerateWhenMissing: true,
      persistGeneratedToken: true,
    });

    (expect* result.warnings.some((message) => message.includes("saving to config"))).is-truthy();
    (expect* writeConfigFileMock).toHaveBeenCalledWith(
      expect.objectContaining({
        gateway: {
          auth: {
            mode: "token",
            token: "generated-token",
          },
        },
      }),
    );
  });

  (deftest "drops generated plaintext when config changes to SecretRef before persist", async () => {
    readConfigFileSnapshotMock.mockResolvedValue({
      exists: true,
      valid: true,
      config: {
        gateway: {
          auth: {
            token: "${OPENCLAW_GATEWAY_TOKEN}",
          },
        },
      },
      issues: [],
    });
    resolveSecretInputRefMock.mockReturnValueOnce({ ref: undefined }).mockReturnValueOnce({
      ref: { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_TOKEN" },
    });

    const result = await resolveGatewayInstallToken({
      config: {
        gateway: { auth: { mode: "token" } },
      } as OpenClawConfig,
      env: {} as NodeJS.ProcessEnv,
      autoGenerateWhenMissing: true,
      persistGeneratedToken: true,
    });

    (expect* result.token).toBeUndefined();
    (expect* 
      result.warnings.some((message) => message.includes("skipping plaintext token persistence")),
    ).is-truthy();
    (expect* writeConfigFileMock).not.toHaveBeenCalled();
  });

  (deftest "does not auto-generate when inferred mode has password SecretRef configured", async () => {
    shouldRequireGatewayTokenForInstallMock.mockReturnValue(false);

    const result = await resolveGatewayInstallToken({
      config: {
        gateway: {
          auth: {
            password: { source: "env", provider: "default", id: "GATEWAY_PASSWORD" },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      } as OpenClawConfig,
      env: {} as NodeJS.ProcessEnv,
      autoGenerateWhenMissing: true,
      persistGeneratedToken: true,
    });

    (expect* result.token).toBeUndefined();
    (expect* result.unavailableReason).toBeUndefined();
    (expect* result.warnings.some((message) => message.includes("Auto-generated"))).is(false);
    (expect* writeConfigFileMock).not.toHaveBeenCalled();
  });

  (deftest "skips token SecretRef resolution when token auth is not required", async () => {
    const tokenRef = { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_TOKEN" };
    resolveSecretInputRefMock.mockReturnValue({ ref: tokenRef });
    shouldRequireGatewayTokenForInstallMock.mockReturnValue(false);

    const result = await resolveGatewayInstallToken({
      config: {
        gateway: {
          auth: {
            mode: "password",
            token: tokenRef,
          },
        },
      } as OpenClawConfig,
      env: {} as NodeJS.ProcessEnv,
    });

    (expect* resolveSecretRefValuesMock).not.toHaveBeenCalled();
    (expect* result.unavailableReason).toBeUndefined();
    (expect* result.warnings).is-equal([]);
    (expect* result.token).toBeUndefined();
    (expect* result.tokenRefConfigured).is(true);
  });
});
