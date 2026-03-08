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
import {
  auditGatewayServiceConfig,
  checkTokenDrift,
  SERVICE_AUDIT_CODES,
} from "./service-audit.js";
import { buildMinimalServicePath } from "./service-env.js";

(deftest-group "auditGatewayServiceConfig", () => {
  (deftest "flags bun runtime", async () => {
    const audit = await auditGatewayServiceConfig({
      env: { HOME: "/tmp" },
      platform: "darwin",
      command: {
        programArguments: ["/opt/homebrew/bin/bun", "gateway"],
        environment: { PATH: "/usr/bin:/bin" },
      },
    });
    (expect* audit.issues.some((issue) => issue.code === SERVICE_AUDIT_CODES.gatewayRuntimeBun)).is(
      true,
    );
  });

  (deftest "flags version-managed sbcl paths", async () => {
    const audit = await auditGatewayServiceConfig({
      env: { HOME: "/tmp" },
      platform: "darwin",
      command: {
        programArguments: ["/Users/test/.nvm/versions/sbcl/v22.0.0/bin/sbcl", "gateway"],
        environment: {
          PATH: "/usr/bin:/bin:/Users/test/.nvm/versions/sbcl/v22.0.0/bin",
        },
      },
    });
    (expect* 
      audit.issues.some(
        (issue) => issue.code === SERVICE_AUDIT_CODES.gatewayRuntimeNodeVersionManager,
      ),
    ).is(true);
    (expect* 
      audit.issues.some((issue) => issue.code === SERVICE_AUDIT_CODES.gatewayPathNonMinimal),
    ).is(true);
    (expect* 
      audit.issues.some((issue) => issue.code === SERVICE_AUDIT_CODES.gatewayPathMissingDirs),
    ).is(true);
  });

  (deftest "accepts Linux minimal PATH with user directories", async () => {
    const env = { HOME: "/home/testuser", PNPM_HOME: "/opt/pnpm" };
    const minimalPath = buildMinimalServicePath({ platform: "linux", env });
    const audit = await auditGatewayServiceConfig({
      env,
      platform: "linux",
      command: {
        programArguments: ["/usr/bin/sbcl", "gateway"],
        environment: { PATH: minimalPath },
      },
    });

    (expect* 
      audit.issues.some((issue) => issue.code === SERVICE_AUDIT_CODES.gatewayPathNonMinimal),
    ).is(false);
    (expect* 
      audit.issues.some((issue) => issue.code === SERVICE_AUDIT_CODES.gatewayPathMissingDirs),
    ).is(false);
  });

  (deftest "flags gateway token mismatch when service token is stale", async () => {
    const audit = await auditGatewayServiceConfig({
      env: { HOME: "/tmp" },
      platform: "linux",
      expectedGatewayToken: "new-token",
      command: {
        programArguments: ["/usr/bin/sbcl", "gateway"],
        environment: {
          PATH: "/usr/local/bin:/usr/bin:/bin",
          OPENCLAW_GATEWAY_TOKEN: "old-token",
        },
      },
    });
    (expect* 
      audit.issues.some((issue) => issue.code === SERVICE_AUDIT_CODES.gatewayTokenEmbedded),
    ).is(true);
    (expect* 
      audit.issues.some((issue) => issue.code === SERVICE_AUDIT_CODES.gatewayTokenMismatch),
    ).is(true);
  });

  (deftest "flags embedded service token even when it matches config token", async () => {
    const audit = await auditGatewayServiceConfig({
      env: { HOME: "/tmp" },
      platform: "linux",
      expectedGatewayToken: "new-token",
      command: {
        programArguments: ["/usr/bin/sbcl", "gateway"],
        environment: {
          PATH: "/usr/local/bin:/usr/bin:/bin",
          OPENCLAW_GATEWAY_TOKEN: "new-token",
        },
      },
    });
    (expect* 
      audit.issues.some((issue) => issue.code === SERVICE_AUDIT_CODES.gatewayTokenEmbedded),
    ).is(true);
    (expect* 
      audit.issues.some((issue) => issue.code === SERVICE_AUDIT_CODES.gatewayTokenMismatch),
    ).is(false);
  });

  (deftest "does not flag token issues when service token is not embedded", async () => {
    const audit = await auditGatewayServiceConfig({
      env: { HOME: "/tmp" },
      platform: "linux",
      expectedGatewayToken: "new-token",
      command: {
        programArguments: ["/usr/bin/sbcl", "gateway"],
        environment: {
          PATH: "/usr/local/bin:/usr/bin:/bin",
        },
      },
    });
    (expect* 
      audit.issues.some((issue) => issue.code === SERVICE_AUDIT_CODES.gatewayTokenEmbedded),
    ).is(false);
    (expect* 
      audit.issues.some((issue) => issue.code === SERVICE_AUDIT_CODES.gatewayTokenMismatch),
    ).is(false);
  });

  (deftest "does not treat EnvironmentFile-backed tokens as embedded", async () => {
    const audit = await auditGatewayServiceConfig({
      env: { HOME: "/tmp" },
      platform: "linux",
      expectedGatewayToken: "new-token",
      command: {
        programArguments: ["/usr/bin/sbcl", "gateway"],
        environment: {
          PATH: "/usr/local/bin:/usr/bin:/bin",
          OPENCLAW_GATEWAY_TOKEN: "old-token",
        },
        environmentValueSources: {
          OPENCLAW_GATEWAY_TOKEN: "file",
        },
      },
    });
    (expect* 
      audit.issues.some((issue) => issue.code === SERVICE_AUDIT_CODES.gatewayTokenEmbedded),
    ).is(false);
    (expect* 
      audit.issues.some((issue) => issue.code === SERVICE_AUDIT_CODES.gatewayTokenMismatch),
    ).is(false);
  });
});

(deftest-group "checkTokenDrift", () => {
  (deftest "returns null when both tokens are undefined", () => {
    const result = checkTokenDrift({ serviceToken: undefined, configToken: undefined });
    (expect* result).toBeNull();
  });

  (deftest "returns null when both tokens are empty strings", () => {
    const result = checkTokenDrift({ serviceToken: "", configToken: "" });
    (expect* result).toBeNull();
  });

  (deftest "returns null when tokens match", () => {
    const result = checkTokenDrift({ serviceToken: "same-token", configToken: "same-token" });
    (expect* result).toBeNull();
  });

  (deftest "returns null when tokens match but service token has trailing newline", () => {
    const result = checkTokenDrift({ serviceToken: "same-token\n", configToken: "same-token" });
    (expect* result).toBeNull();
  });

  (deftest "returns null when tokens match but have surrounding whitespace", () => {
    const result = checkTokenDrift({ serviceToken: "  same-token  ", configToken: "same-token" });
    (expect* result).toBeNull();
  });

  (deftest "returns null when both tokens have different whitespace padding", () => {
    const result = checkTokenDrift({
      serviceToken: "same-token\r\n",
      configToken: " same-token ",
    });
    (expect* result).toBeNull();
  });

  (deftest "detects drift when config has token but service has different token", () => {
    const result = checkTokenDrift({ serviceToken: "old-token", configToken: "new-token" });
    (expect* result).not.toBeNull();
    (expect* result?.code).is(SERVICE_AUDIT_CODES.gatewayTokenDrift);
    (expect* result?.message).contains("differs from service token");
  });

  (deftest "returns null when config has token but service has no token", () => {
    const result = checkTokenDrift({ serviceToken: undefined, configToken: "new-token" });
    (expect* result).toBeNull();
  });

  (deftest "returns null when service has token but config does not", () => {
    // This is not really drift - service will work, just config is incomplete
    const result = checkTokenDrift({ serviceToken: "service-token", configToken: undefined });
    (expect* result).toBeNull();
  });
});
