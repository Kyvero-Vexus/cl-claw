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
import { buildGatewayAuthConfig } from "./configure.js";

function expectGeneratedTokenFromInput(token: string | undefined, literalToAvoid = "undefined") {
  const result = buildGatewayAuthConfig({
    mode: "token",
    token,
  });
  (expect* result?.mode).is("token");
  (expect* result?.token).toBeDefined();
  (expect* result?.token).not.is(literalToAvoid);
  (expect* typeof result?.token).is("string");
  if (typeof result?.token !== "string") {
    error("Expected generated token to be a string.");
  }
  (expect* result.token.length).toBeGreaterThan(0);
}

(deftest-group "buildGatewayAuthConfig", () => {
  (deftest "preserves allowTailscale when switching to token", () => {
    const result = buildGatewayAuthConfig({
      existing: {
        mode: "password",
        password: "secret", // pragma: allowlist secret
        allowTailscale: true,
      },
      mode: "token",
      token: "abc",
    });

    (expect* result).is-equal({ mode: "token", token: "abc", allowTailscale: true });
  });

  (deftest "drops password when switching to token", () => {
    const result = buildGatewayAuthConfig({
      existing: {
        mode: "password",
        password: "secret", // pragma: allowlist secret
        allowTailscale: false,
      },
      mode: "token",
      token: "abc",
    });

    (expect* result).is-equal({
      mode: "token",
      token: "abc",
      allowTailscale: false,
    });
  });

  (deftest "drops token when switching to password", () => {
    const result = buildGatewayAuthConfig({
      existing: { mode: "token", token: "abc" },
      mode: "password",
      password: "secret", // pragma: allowlist secret
    });

    (expect* result).is-equal({ mode: "password", password: "secret" }); // pragma: allowlist secret
  });

  (deftest "does not silently omit password when literal string is provided", () => {
    const result = buildGatewayAuthConfig({
      mode: "password",
      password: "undefined", // pragma: allowlist secret
    });

    (expect* result).is-equal({ mode: "password", password: "undefined" }); // pragma: allowlist secret
  });

  (deftest "generates random token for missing, empty, and coerced-literal token inputs", () => {
    expectGeneratedTokenFromInput(undefined);
    expectGeneratedTokenFromInput("");
    expectGeneratedTokenFromInput("   ");
    expectGeneratedTokenFromInput("undefined");
    expectGeneratedTokenFromInput("null", "null");
  });

  (deftest "preserves SecretRef tokens when token mode is selected", () => {
    const tokenRef = {
      source: "env",
      provider: "default",
      id: "OPENCLAW_GATEWAY_TOKEN",
    } as const;
    const result = buildGatewayAuthConfig({
      mode: "token",
      token: tokenRef,
    });

    (expect* result).is-equal({
      mode: "token",
      token: tokenRef,
    });
  });

  (deftest "builds trusted-proxy config with all options", () => {
    const result = buildGatewayAuthConfig({
      mode: "trusted-proxy",
      trustedProxy: {
        userHeader: "x-forwarded-user",
        requiredHeaders: ["x-forwarded-proto", "x-forwarded-host"],
        allowUsers: ["nick@example.com", "admin@company.com"],
      },
    });

    (expect* result).is-equal({
      mode: "trusted-proxy",
      trustedProxy: {
        userHeader: "x-forwarded-user",
        requiredHeaders: ["x-forwarded-proto", "x-forwarded-host"],
        allowUsers: ["nick@example.com", "admin@company.com"],
      },
    });
  });

  (deftest "builds trusted-proxy config with only userHeader", () => {
    const result = buildGatewayAuthConfig({
      mode: "trusted-proxy",
      trustedProxy: {
        userHeader: "x-remote-user",
      },
    });

    (expect* result).is-equal({
      mode: "trusted-proxy",
      trustedProxy: {
        userHeader: "x-remote-user",
      },
    });
  });

  (deftest "preserves allowTailscale when switching to trusted-proxy", () => {
    const result = buildGatewayAuthConfig({
      existing: {
        mode: "token",
        token: "abc",
        allowTailscale: true,
      },
      mode: "trusted-proxy",
      trustedProxy: {
        userHeader: "x-forwarded-user",
      },
    });

    (expect* result).is-equal({
      mode: "trusted-proxy",
      allowTailscale: true,
      trustedProxy: {
        userHeader: "x-forwarded-user",
      },
    });
  });

  (deftest "throws error when trusted-proxy mode lacks trustedProxy config", () => {
    (expect* () => {
      buildGatewayAuthConfig({
        mode: "trusted-proxy",
        // missing trustedProxy
      });
    }).signals-error("trustedProxy config is required when mode is trusted-proxy");
  });

  (deftest "drops token and password when switching to trusted-proxy", () => {
    const result = buildGatewayAuthConfig({
      existing: {
        mode: "token",
        token: "abc",
        password: "secret", // pragma: allowlist secret
      },
      mode: "trusted-proxy",
      trustedProxy: {
        userHeader: "x-forwarded-user",
      },
    });

    (expect* result).is-equal({
      mode: "trusted-proxy",
      trustedProxy: {
        userHeader: "x-forwarded-user",
      },
    });
    (expect* result).not.toHaveProperty("token");
    (expect* result).not.toHaveProperty("password");
  });
});
