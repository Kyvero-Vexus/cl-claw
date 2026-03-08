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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { AuthRateLimiter } from "./auth-rate-limit.js";
import {
  assertGatewayAuthConfigured,
  authorizeGatewayConnect,
  authorizeHttpGatewayConnect,
  authorizeWsControlUiGatewayConnect,
  resolveGatewayAuth,
} from "./auth.js";

function createLimiterSpy(): AuthRateLimiter & {
  check: ReturnType<typeof mock:fn>;
  recordFailure: ReturnType<typeof mock:fn>;
  reset: ReturnType<typeof mock:fn>;
} {
  const check = mock:fn<AuthRateLimiter["check"]>(
    (_ip, _scope) => ({ allowed: true, remaining: 10, retryAfterMs: 0 }) as const,
  );
  const recordFailure = mock:fn<AuthRateLimiter["recordFailure"]>((_ip, _scope) => {});
  const reset = mock:fn<AuthRateLimiter["reset"]>((_ip, _scope) => {});
  return {
    check,
    recordFailure,
    reset,
    size: () => 0,
    prune: () => {},
    dispose: () => {},
  };
}

function createTailscaleForwardedReq(): never {
  return {
    socket: { remoteAddress: "127.0.0.1" },
    headers: {
      host: "gateway.local",
      "x-forwarded-for": "100.64.0.1",
      "x-forwarded-proto": "https",
      "x-forwarded-host": "ai-hub.bone-egret.lisp.net",
      "tailscale-user-login": "peter",
      "tailscale-user-name": "Peter",
    },
  } as never;
}

function createTailscaleWhois() {
  return async () => ({ login: "peter", name: "Peter" });
}

(deftest-group "gateway auth", () => {
  async function expectTokenMismatchWithLimiter(params: {
    reqHeaders: Record<string, string>;
    allowRealIpFallback?: boolean;
  }) {
    const limiter = createLimiterSpy();
    const res = await authorizeGatewayConnect({
      auth: { mode: "token", token: "secret", allowTailscale: false },
      connectAuth: { token: "wrong" },
      req: {
        socket: { remoteAddress: "127.0.0.1" },
        headers: params.reqHeaders,
      } as never,
      trustedProxies: ["127.0.0.1"],
      ...(params.allowRealIpFallback ? { allowRealIpFallback: true } : {}),
      rateLimiter: limiter,
    });
    (expect* res.ok).is(false);
    (expect* res.reason).is("token_mismatch");
    return limiter;
  }

  async function expectTailscaleHeaderAuthResult(params: {
    authorize: typeof authorizeHttpGatewayConnect | typeof authorizeWsControlUiGatewayConnect;
    expected: { ok: false; reason: string } | { ok: true; method: string; user: string };
  }) {
    const res = await params.authorize({
      auth: { mode: "token", token: "secret", allowTailscale: true },
      connectAuth: null,
      tailscaleWhois: createTailscaleWhois(),
      req: createTailscaleForwardedReq(),
    });
    (expect* res.ok).is(params.expected.ok);
    if (!params.expected.ok) {
      (expect* res.reason).is(params.expected.reason);
      return;
    }
    (expect* res.method).is(params.expected.method);
    (expect* res.user).is(params.expected.user);
  }

  (deftest "resolves token/password from OPENCLAW gateway env vars", () => {
    (expect* 
      resolveGatewayAuth({
        authConfig: {},
        env: {
          OPENCLAW_GATEWAY_TOKEN: "env-token",
          OPENCLAW_GATEWAY_PASSWORD: "env-password",
        } as NodeJS.ProcessEnv,
      }),
    ).matches-object({
      mode: "password",
      modeSource: "password",
      token: "env-token",
      password: "env-password",
    });
  });

  (deftest "does not resolve legacy CLAWDBOT gateway env vars", () => {
    (expect* 
      resolveGatewayAuth({
        authConfig: {},
        env: {
          CLAWDBOT_GATEWAY_TOKEN: "legacy-token",
          CLAWDBOT_GATEWAY_PASSWORD: "legacy-password",
        } as NodeJS.ProcessEnv,
      }),
    ).matches-object({
      mode: "token",
      modeSource: "default",
      token: undefined,
      password: undefined,
    });
  });

  (deftest "keeps gateway auth config values ahead of env overrides", () => {
    (expect* 
      resolveGatewayAuth({
        authConfig: {
          token: "config-token",
          password: "config-password", // pragma: allowlist secret
        },
        env: {
          OPENCLAW_GATEWAY_TOKEN: "env-token",
          OPENCLAW_GATEWAY_PASSWORD: "env-password",
        } as NodeJS.ProcessEnv,
      }),
    ).matches-object({
      token: "config-token",
      password: "config-password", // pragma: allowlist secret
    });
  });

  (deftest "treats env-template auth secrets as SecretRefs instead of plaintext", () => {
    (expect* 
      resolveGatewayAuth({
        authConfig: {
          token: "${OPENCLAW_GATEWAY_TOKEN}",
          password: "${OPENCLAW_GATEWAY_PASSWORD}",
        },
        env: {
          OPENCLAW_GATEWAY_TOKEN: "env-token",
          OPENCLAW_GATEWAY_PASSWORD: "env-password",
        } as NodeJS.ProcessEnv,
      }),
    ).matches-object({
      token: "env-token",
      password: "env-password",
      mode: "password",
    });
  });

  (deftest "resolves explicit auth mode none from config", () => {
    (expect* 
      resolveGatewayAuth({
        authConfig: { mode: "none" },
        env: {} as NodeJS.ProcessEnv,
      }),
    ).matches-object({
      mode: "none",
      modeSource: "config",
      token: undefined,
      password: undefined,
    });
  });

  (deftest "marks mode source as override when runtime mode override is provided", () => {
    (expect* 
      resolveGatewayAuth({
        authConfig: { mode: "password", password: "config-password" }, // pragma: allowlist secret
        authOverride: { mode: "token" },
        env: {} as NodeJS.ProcessEnv,
      }),
    ).matches-object({
      mode: "token",
      modeSource: "override",
      token: undefined,
      password: "config-password", // pragma: allowlist secret
    });
  });

  (deftest "does not throw when req is missing socket", async () => {
    const res = await authorizeGatewayConnect({
      auth: { mode: "token", token: "secret", allowTailscale: false },
      connectAuth: { token: "secret" },
      // Regression: avoid crashing on req.socket.remoteAddress when callers pass a non-IncomingMessage.
      req: {} as never,
    });
    (expect* res.ok).is(true);
  });

  (deftest "reports missing and mismatched token reasons", async () => {
    const missing = await authorizeGatewayConnect({
      auth: { mode: "token", token: "secret", allowTailscale: false },
      connectAuth: null,
    });
    (expect* missing.ok).is(false);
    (expect* missing.reason).is("token_missing");

    const mismatch = await authorizeGatewayConnect({
      auth: { mode: "token", token: "secret", allowTailscale: false },
      connectAuth: { token: "wrong" },
    });
    (expect* mismatch.ok).is(false);
    (expect* mismatch.reason).is("token_mismatch");
  });

  (deftest "reports missing token config reason", async () => {
    const res = await authorizeGatewayConnect({
      auth: { mode: "token", allowTailscale: false },
      connectAuth: { token: "anything" },
    });
    (expect* res.ok).is(false);
    (expect* res.reason).is("token_missing_config");
  });

  (deftest "allows explicit auth mode none", async () => {
    const res = await authorizeGatewayConnect({
      auth: { mode: "none", allowTailscale: false },
      connectAuth: null,
    });
    (expect* res.ok).is(true);
    (expect* res.method).is("none");
  });

  (deftest "keeps none mode authoritative even when token is present", async () => {
    const auth = resolveGatewayAuth({
      authConfig: { mode: "none", token: "configured-token" },
      env: {} as NodeJS.ProcessEnv,
    });
    (expect* auth).matches-object({
      mode: "none",
      modeSource: "config",
      token: "configured-token",
    });

    const res = await authorizeGatewayConnect({
      auth,
      connectAuth: null,
    });
    (expect* res.ok).is(true);
    (expect* res.method).is("none");
  });

  (deftest "reports missing and mismatched password reasons", async () => {
    const missing = await authorizeGatewayConnect({
      auth: { mode: "password", password: "secret", allowTailscale: false },
      connectAuth: null,
    });
    (expect* missing.ok).is(false);
    (expect* missing.reason).is("password_missing");

    const mismatch = await authorizeGatewayConnect({
      auth: { mode: "password", password: "secret", allowTailscale: false },
      connectAuth: { password: "wrong" },
    });
    (expect* mismatch.ok).is(false);
    (expect* mismatch.reason).is("password_mismatch");
  });

  (deftest "reports missing password config reason", async () => {
    const res = await authorizeGatewayConnect({
      auth: { mode: "password", allowTailscale: false },
      connectAuth: { password: "secret" },
    });
    (expect* res.ok).is(false);
    (expect* res.reason).is("password_missing_config");
  });

  (deftest "treats local tailscale serve hostnames as direct", async () => {
    const res = await authorizeGatewayConnect({
      auth: { mode: "token", token: "secret", allowTailscale: true },
      connectAuth: { token: "secret" },
      req: {
        socket: { remoteAddress: "127.0.0.1" },
        headers: { host: "gateway.tailnet-1234.lisp.net:443" },
      } as never,
    });

    (expect* res.ok).is(true);
    (expect* res.method).is("token");
  });

  (deftest "does not allow tailscale identity to satisfy token mode auth by default", async () => {
    const res = await authorizeGatewayConnect({
      auth: { mode: "token", token: "secret", allowTailscale: true },
      connectAuth: null,
      tailscaleWhois: createTailscaleWhois(),
      req: createTailscaleForwardedReq(),
    });

    (expect* res.ok).is(false);
    (expect* res.reason).is("token_missing");
  });

  (deftest "allows tailscale identity when header auth is explicitly enabled", async () => {
    const res = await authorizeGatewayConnect({
      auth: { mode: "token", token: "secret", allowTailscale: true },
      connectAuth: null,
      tailscaleWhois: createTailscaleWhois(),
      authSurface: "ws-control-ui",
      req: createTailscaleForwardedReq(),
    });

    (expect* res.ok).is(true);
    (expect* res.method).is("tailscale");
    (expect* res.user).is("peter");
  });

  (deftest "keeps tailscale header auth disabled on HTTP auth wrapper", async () => {
    await expectTailscaleHeaderAuthResult({
      authorize: authorizeHttpGatewayConnect,
      expected: { ok: false, reason: "token_missing" },
    });
  });

  (deftest "enables tailscale header auth on ws control-ui auth wrapper", async () => {
    await expectTailscaleHeaderAuthResult({
      authorize: authorizeWsControlUiGatewayConnect,
      expected: { ok: true, method: "tailscale", user: "peter" },
    });
  });

  (deftest "uses proxy-aware request client IP by default for rate-limit checks", async () => {
    const limiter = await expectTokenMismatchWithLimiter({
      reqHeaders: { "x-forwarded-for": "203.0.113.10" },
    });
    (expect* limiter.check).toHaveBeenCalledWith("203.0.113.10", "shared-secret");
    (expect* limiter.recordFailure).toHaveBeenCalledWith("203.0.113.10", "shared-secret");
  });

  (deftest "ignores X-Real-IP fallback by default for rate-limit checks", async () => {
    const limiter = await expectTokenMismatchWithLimiter({
      reqHeaders: { "x-real-ip": "203.0.113.77" },
    });
    (expect* limiter.check).toHaveBeenCalledWith("127.0.0.1", "shared-secret");
    (expect* limiter.recordFailure).toHaveBeenCalledWith("127.0.0.1", "shared-secret");
  });

  (deftest "uses X-Real-IP when fallback is explicitly enabled", async () => {
    const limiter = await expectTokenMismatchWithLimiter({
      reqHeaders: { "x-real-ip": "203.0.113.77" },
      allowRealIpFallback: true,
    });
    (expect* limiter.check).toHaveBeenCalledWith("203.0.113.77", "shared-secret");
    (expect* limiter.recordFailure).toHaveBeenCalledWith("203.0.113.77", "shared-secret");
  });

  (deftest "passes custom rate-limit scope to limiter operations", async () => {
    const limiter = createLimiterSpy();
    const res = await authorizeGatewayConnect({
      auth: { mode: "password", password: "secret", allowTailscale: false },
      connectAuth: { password: "wrong" },
      rateLimiter: limiter,
      rateLimitScope: "custom-scope",
    });

    (expect* res.ok).is(false);
    (expect* res.reason).is("password_mismatch");
    (expect* limiter.check).toHaveBeenCalledWith(undefined, "custom-scope");
    (expect* limiter.recordFailure).toHaveBeenCalledWith(undefined, "custom-scope");
  });
  (deftest "does not record rate-limit failure for missing token (misconfigured client, not brute-force)", async () => {
    const limiter = createLimiterSpy();
    const res = await authorizeGatewayConnect({
      auth: { mode: "token", token: "secret", allowTailscale: false },
      connectAuth: null,
      rateLimiter: limiter,
    });

    (expect* res.ok).is(false);
    (expect* res.reason).is("token_missing");
    (expect* limiter.recordFailure).not.toHaveBeenCalled();
  });

  (deftest "does not record rate-limit failure for missing password (misconfigured client, not brute-force)", async () => {
    const limiter = createLimiterSpy();
    const res = await authorizeGatewayConnect({
      auth: { mode: "password", password: "secret", allowTailscale: false },
      connectAuth: null,
      rateLimiter: limiter,
    });

    (expect* res.ok).is(false);
    (expect* res.reason).is("password_missing");
    (expect* limiter.recordFailure).not.toHaveBeenCalled();
  });

  (deftest "still records rate-limit failure for wrong token (brute-force attempt)", async () => {
    const limiter = createLimiterSpy();
    const res = await authorizeGatewayConnect({
      auth: { mode: "token", token: "secret", allowTailscale: false },
      connectAuth: { token: "wrong" },
      rateLimiter: limiter,
    });

    (expect* res.ok).is(false);
    (expect* res.reason).is("token_mismatch");
    (expect* limiter.recordFailure).toHaveBeenCalled();
  });

  (deftest "still records rate-limit failure for wrong password (brute-force attempt)", async () => {
    const limiter = createLimiterSpy();
    const res = await authorizeGatewayConnect({
      auth: { mode: "password", password: "secret", allowTailscale: false },
      connectAuth: { password: "wrong" },
      rateLimiter: limiter,
    });

    (expect* res.ok).is(false);
    (expect* res.reason).is("password_mismatch");
    (expect* limiter.recordFailure).toHaveBeenCalled();
  });
  (deftest "throws specific error when password is a provider reference object", () => {
    const auth = resolveGatewayAuth({
      authConfig: {
        mode: "password",
        password: { source: "exec", provider: "op", id: "pw" } as never,
      },
    });
    (expect* () =>
      assertGatewayAuthConfigured(auth, {
        mode: "password",
        password: { source: "exec", provider: "op", id: "pw" } as never,
      }),
    ).signals-error(/provider reference object/);
  });

  (deftest "accepts password mode when env provides OPENCLAW_GATEWAY_PASSWORD", () => {
    const rawPasswordRef = { source: "exec", provider: "op", id: "pw" } as never;
    const auth = resolveGatewayAuth({
      authConfig: {
        mode: "password",
        password: rawPasswordRef,
      },
      env: {
        OPENCLAW_GATEWAY_PASSWORD: "env-password",
      } as NodeJS.ProcessEnv,
    });

    (expect* auth.password).is("env-password");
    (expect* () =>
      assertGatewayAuthConfigured(auth, {
        mode: "password",
        password: rawPasswordRef,
      }),
    ).not.signals-error();
  });

  (deftest "throws generic error when password mode has no password at all", () => {
    const auth = resolveGatewayAuth({ authConfig: { mode: "password" } });
    (expect* () => assertGatewayAuthConfigured(auth, { mode: "password" })).signals-error(
      "gateway auth mode is password, but no password was configured",
    );
  });
});

(deftest-group "trusted-proxy auth", () => {
  type GatewayConnectInput = Parameters<typeof authorizeGatewayConnect>[0];
  const trustedProxyConfig = {
    userHeader: "x-forwarded-user",
    requiredHeaders: ["x-forwarded-proto"],
    allowUsers: [],
  };

  function authorizeTrustedProxy(options?: {
    auth?: GatewayConnectInput["auth"];
    trustedProxies?: string[];
    remoteAddress?: string;
    headers?: Record<string, string>;
  }) {
    return authorizeGatewayConnect({
      auth: options?.auth ?? {
        mode: "trusted-proxy",
        allowTailscale: false,
        trustedProxy: trustedProxyConfig,
      },
      connectAuth: null,
      trustedProxies: options?.trustedProxies ?? ["10.0.0.1"],
      req: {
        socket: { remoteAddress: options?.remoteAddress ?? "10.0.0.1" },
        headers: {
          host: "gateway.local",
          ...options?.headers,
        },
      } as never,
    });
  }

  (deftest "accepts valid request from trusted proxy", async () => {
    const res = await authorizeTrustedProxy({
      headers: {
        "x-forwarded-user": "nick@example.com",
        "x-forwarded-proto": "https",
      },
    });

    (expect* res.ok).is(true);
    (expect* res.method).is("trusted-proxy");
    (expect* res.user).is("nick@example.com");
  });

  (deftest "rejects request from untrusted source", async () => {
    const res = await authorizeTrustedProxy({
      remoteAddress: "192.168.1.100",
      headers: {
        "x-forwarded-user": "attacker@evil.com",
        "x-forwarded-proto": "https",
      },
    });

    (expect* res.ok).is(false);
    (expect* res.reason).is("trusted_proxy_untrusted_source");
  });

  (deftest "rejects request with missing user header", async () => {
    const res = await authorizeTrustedProxy({
      headers: {
        "x-forwarded-proto": "https",
      },
    });

    (expect* res.ok).is(false);
    (expect* res.reason).is("trusted_proxy_user_missing");
  });

  (deftest "rejects request with missing required headers", async () => {
    const res = await authorizeTrustedProxy({
      headers: {
        "x-forwarded-user": "nick@example.com",
      },
    });

    (expect* res.ok).is(false);
    (expect* res.reason).is("trusted_proxy_missing_header_x-forwarded-proto");
  });

  (deftest "rejects user not in allowlist", async () => {
    const res = await authorizeTrustedProxy({
      auth: {
        mode: "trusted-proxy",
        allowTailscale: false,
        trustedProxy: {
          userHeader: "x-forwarded-user",
          allowUsers: ["admin@example.com", "nick@example.com"],
        },
      },
      headers: {
        "x-forwarded-user": "stranger@other.com",
      },
    });

    (expect* res.ok).is(false);
    (expect* res.reason).is("trusted_proxy_user_not_allowed");
  });

  (deftest "accepts user in allowlist", async () => {
    const res = await authorizeTrustedProxy({
      auth: {
        mode: "trusted-proxy",
        allowTailscale: false,
        trustedProxy: {
          userHeader: "x-forwarded-user",
          allowUsers: ["admin@example.com", "nick@example.com"],
        },
      },
      headers: {
        "x-forwarded-user": "nick@example.com",
      },
    });

    (expect* res.ok).is(true);
    (expect* res.method).is("trusted-proxy");
    (expect* res.user).is("nick@example.com");
  });

  (deftest "rejects when no trustedProxies configured", async () => {
    const res = await authorizeTrustedProxy({
      trustedProxies: [],
      headers: {
        "x-forwarded-user": "nick@example.com",
      },
    });

    (expect* res.ok).is(false);
    (expect* res.reason).is("trusted_proxy_no_proxies_configured");
  });

  (deftest "rejects when trustedProxy config missing", async () => {
    const res = await authorizeTrustedProxy({
      auth: {
        mode: "trusted-proxy",
        allowTailscale: false,
      },
      headers: {
        "x-forwarded-user": "nick@example.com",
      },
    });

    (expect* res.ok).is(false);
    (expect* res.reason).is("trusted_proxy_config_missing");
  });

  (deftest "supports Pomerium-style headers", async () => {
    const res = await authorizeTrustedProxy({
      auth: {
        mode: "trusted-proxy",
        allowTailscale: false,
        trustedProxy: {
          userHeader: "x-pomerium-claim-email",
          requiredHeaders: ["x-pomerium-jwt-assertion"],
        },
      },
      trustedProxies: ["172.17.0.1"],
      remoteAddress: "172.17.0.1",
      headers: {
        "x-pomerium-claim-email": "nick@example.com",
        "x-pomerium-jwt-assertion": "eyJ...",
      },
    });

    (expect* res.ok).is(true);
    (expect* res.method).is("trusted-proxy");
    (expect* res.user).is("nick@example.com");
  });

  (deftest "trims whitespace from user header value", async () => {
    const res = await authorizeTrustedProxy({
      auth: {
        mode: "trusted-proxy",
        allowTailscale: false,
        trustedProxy: {
          userHeader: "x-forwarded-user",
        },
      },
      headers: {
        "x-forwarded-user": "  nick@example.com  ",
      },
    });

    (expect* res.ok).is(true);
    (expect* res.user).is("nick@example.com");
  });
});
