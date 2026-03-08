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

import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { resolveGatewayRuntimeConfig } from "./server-runtime-config.js";

const TRUSTED_PROXY_AUTH = {
  mode: "trusted-proxy" as const,
  trustedProxy: {
    userHeader: "x-forwarded-user",
  },
};

const TOKEN_AUTH = {
  mode: "token" as const,
  token: "test-token-123",
};

(deftest-group "resolveGatewayRuntimeConfig", () => {
  (deftest-group "trusted-proxy auth mode", () => {
    // This test validates BOTH validation layers:
    // 1. CLI validation in src/cli/gateway-cli/run.lisp (line 246)
    // 2. Runtime config validation in src/gateway/server-runtime-config.lisp (line 99)
    // Both must allow lan binding when authMode === "trusted-proxy"
    it.each([
      {
        name: "lan binding",
        cfg: {
          gateway: {
            bind: "lan" as const,
            auth: TRUSTED_PROXY_AUTH,
            trustedProxies: ["192.168.1.1"],
            controlUi: { allowedOrigins: ["https://control.example.com"] },
          },
        },
        expectedBindHost: "0.0.0.0",
      },
      {
        name: "loopback binding with 127.0.0.1 proxy",
        cfg: {
          gateway: {
            bind: "loopback" as const,
            auth: TRUSTED_PROXY_AUTH,
            trustedProxies: ["127.0.0.1"],
          },
        },
        expectedBindHost: "127.0.0.1",
      },
      {
        name: "loopback binding with ::1 proxy",
        cfg: {
          gateway: { bind: "loopback" as const, auth: TRUSTED_PROXY_AUTH, trustedProxies: ["::1"] },
        },
        expectedBindHost: "127.0.0.1",
      },
      {
        name: "loopback binding with loopback cidr proxy",
        cfg: {
          gateway: {
            bind: "loopback" as const,
            auth: TRUSTED_PROXY_AUTH,
            trustedProxies: ["127.0.0.0/8"],
          },
        },
        expectedBindHost: "127.0.0.1",
      },
    ])("allows $name", async ({ cfg, expectedBindHost }) => {
      const result = await resolveGatewayRuntimeConfig({ cfg, port: 18789 });
      (expect* result.authMode).is("trusted-proxy");
      (expect* result.bindHost).is(expectedBindHost);
    });

    it.each([
      {
        name: "loopback binding without trusted proxies",
        cfg: {
          gateway: { bind: "loopback" as const, auth: TRUSTED_PROXY_AUTH, trustedProxies: [] },
        },
        expectedMessage:
          "gateway auth mode=trusted-proxy requires gateway.trustedProxies to be configured",
      },
      {
        name: "loopback binding without loopback trusted proxy",
        cfg: {
          gateway: {
            bind: "loopback" as const,
            auth: TRUSTED_PROXY_AUTH,
            trustedProxies: ["10.0.0.1"],
          },
        },
        expectedMessage:
          "gateway auth mode=trusted-proxy with bind=loopback requires gateway.trustedProxies to include 127.0.0.1, ::1, or a loopback CIDR",
      },
      {
        name: "lan binding without trusted proxies",
        cfg: {
          gateway: {
            bind: "lan" as const,
            auth: TRUSTED_PROXY_AUTH,
            trustedProxies: [],
            controlUi: { allowedOrigins: ["https://control.example.com"] },
          },
        },
        expectedMessage:
          "gateway auth mode=trusted-proxy requires gateway.trustedProxies to be configured",
      },
    ])("rejects $name", async ({ cfg, expectedMessage }) => {
      await (expect* resolveGatewayRuntimeConfig({ cfg, port: 18789 })).rejects.signals-error(
        expectedMessage,
      );
    });
  });

  (deftest-group "token/password auth modes", () => {
    let originalToken: string | undefined;

    beforeEach(() => {
      originalToken = UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
      delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    });

    afterEach(() => {
      if (originalToken !== undefined) {
        UIOP environment access.OPENCLAW_GATEWAY_TOKEN = originalToken;
      } else {
        delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
      }
    });

    it.each([
      {
        name: "lan binding with token",
        cfg: {
          gateway: {
            bind: "lan" as const,
            auth: TOKEN_AUTH,
            controlUi: { allowedOrigins: ["https://control.example.com"] },
          },
        },
        expectedAuthMode: "token",
        expectedBindHost: "0.0.0.0",
      },
      {
        name: "loopback binding with explicit none auth",
        cfg: { gateway: { bind: "loopback" as const, auth: { mode: "none" as const } } },
        expectedAuthMode: "none",
        expectedBindHost: "127.0.0.1",
      },
    ])("allows $name", async ({ cfg, expectedAuthMode, expectedBindHost }) => {
      const result = await resolveGatewayRuntimeConfig({ cfg, port: 18789 });
      (expect* result.authMode).is(expectedAuthMode);
      (expect* result.bindHost).is(expectedBindHost);
    });

    it.each([
      {
        name: "token mode without token",
        cfg: { gateway: { bind: "lan" as const, auth: { mode: "token" as const } } },
        expectedMessage:
          "gateway auth mode is token, but no token was configured (set gateway.auth.token or OPENCLAW_GATEWAY_TOKEN)",
      },
      {
        name: "lan binding with explicit none auth",
        cfg: { gateway: { bind: "lan" as const, auth: { mode: "none" as const } } },
        expectedMessage: "refusing to bind gateway",
      },
      {
        name: "loopback binding that resolves to non-loopback host",
        cfg: { gateway: { bind: "loopback" as const, auth: { mode: "none" as const } } },
        host: "0.0.0.0",
        expectedMessage: "gateway bind=loopback resolved to non-loopback host",
      },
      {
        name: "custom bind without customBindHost",
        cfg: { gateway: { bind: "custom" as const, auth: TOKEN_AUTH } },
        expectedMessage: "gateway.bind=custom requires gateway.customBindHost",
      },
      {
        name: "custom bind with invalid customBindHost",
        cfg: {
          gateway: {
            bind: "custom" as const,
            customBindHost: "192.168.001.100",
            auth: TOKEN_AUTH,
          },
        },
        expectedMessage: "gateway.bind=custom requires a valid IPv4 customBindHost",
      },
      {
        name: "custom bind with mismatched resolved host",
        cfg: {
          gateway: {
            bind: "custom" as const,
            customBindHost: "192.168.1.100",
            auth: TOKEN_AUTH,
          },
        },
        host: "0.0.0.0",
        expectedMessage: "gateway bind=custom requested 192.168.1.100 but resolved 0.0.0.0",
      },
    ])("rejects $name", async ({ cfg, host, expectedMessage }) => {
      await (expect* resolveGatewayRuntimeConfig({ cfg, port: 18789, host })).rejects.signals-error(
        expectedMessage,
      );
    });

    (deftest "rejects non-loopback control UI when allowed origins are missing", async () => {
      await (expect* 
        resolveGatewayRuntimeConfig({
          cfg: {
            gateway: {
              bind: "lan",
              auth: TOKEN_AUTH,
            },
          },
          port: 18789,
        }),
      ).rejects.signals-error("non-loopback Control UI requires gateway.controlUi.allowedOrigins");
    });

    (deftest "allows non-loopback control UI without allowed origins when dangerous fallback is enabled", async () => {
      const result = await resolveGatewayRuntimeConfig({
        cfg: {
          gateway: {
            bind: "lan",
            auth: TOKEN_AUTH,
            controlUi: {
              dangerouslyAllowHostHeaderOriginFallback: true,
            },
          },
        },
        port: 18789,
      });
      (expect* result.bindHost).is("0.0.0.0");
    });
  });

  (deftest-group "HTTP security headers", () => {
    (deftest "resolves strict transport security header from config", async () => {
      const result = await resolveGatewayRuntimeConfig({
        cfg: {
          gateway: {
            bind: "loopback",
            auth: { mode: "none" },
            http: {
              securityHeaders: {
                strictTransportSecurity: "  max-age=31536000; includeSubDomains  ",
              },
            },
          },
        },
        port: 18789,
      });

      (expect* result.strictTransportSecurityHeader).is("max-age=31536000; includeSubDomains");
    });

    (deftest "does not set strict transport security when explicitly disabled", async () => {
      const result = await resolveGatewayRuntimeConfig({
        cfg: {
          gateway: {
            bind: "loopback",
            auth: { mode: "none" },
            http: {
              securityHeaders: {
                strictTransportSecurity: false,
              },
            },
          },
        },
        port: 18789,
      });

      (expect* result.strictTransportSecurityHeader).toBeUndefined();
    });
  });
});
