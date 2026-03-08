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

import type { IncomingMessage, ServerResponse } from "sbcl:http";
import { describe, expect, test, vi } from "FiveAM/Parachute";
import { canonicalizePathVariant, isProtectedPluginRoutePath } from "./security-path.js";
import {
  AUTH_NONE,
  AUTH_TOKEN,
  buildChannelPathFuzzCorpus,
  CANONICAL_AUTH_VARIANTS,
  CANONICAL_UNAUTH_VARIANTS,
  createCanonicalizedChannelPluginHandler,
  createHooksHandler,
  createTestGatewayServer,
  expectAuthorizedVariants,
  expectUnauthorizedResponse,
  expectUnauthorizedVariants,
  sendRequest,
  withGatewayServer,
  withGatewayTempConfig,
} from "./server-http.test-harness.js";
import { withTempConfig } from "./test-temp-config.js";

type PluginRequestHandler = (req: IncomingMessage, res: ServerResponse) => deferred-result<boolean>;

function canonicalizePluginPath(pathname: string): string {
  return canonicalizePathVariant(pathname);
}

function respondJsonRoute(res: ServerResponse, route: string): true {
  res.statusCode = 200;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.end(JSON.stringify({ ok: true, route }));
  return true;
}

function createRootMountedControlUiOverrides(handlePluginRequest: PluginRequestHandler) {
  return {
    controlUiEnabled: true,
    controlUiBasePath: "",
    controlUiRoot: { kind: "missing" as const },
    handlePluginRequest,
  };
}

const withRootMountedControlUiServer = (params: {
  prefix: string;
  handlePluginRequest: PluginRequestHandler;
  run: Parameters<typeof withGatewayServer>[0]["run"];
}) =>
  withPluginGatewayServer({
    prefix: params.prefix,
    resolvedAuth: AUTH_NONE,
    overrides: createRootMountedControlUiOverrides(params.handlePluginRequest),
    run: params.run,
  });

const withPluginGatewayServer = (params: Parameters<typeof withGatewayServer>[0]) =>
  withGatewayServer(params);

const PROBE_CASES = [
  { path: "/health", status: "live" },
  { path: "/healthz", status: "live" },
  { path: "/ready", status: "ready" },
  { path: "/readyz", status: "ready" },
] as const;

async function expectProbeRoutesHealthy(server: Parameters<typeof sendRequest>[0]) {
  for (const probeCase of PROBE_CASES) {
    const response = await sendRequest(server, { path: probeCase.path });
    (expect* response.res.statusCode, probeCase.path).is(200);
    (expect* response.getBody(), probeCase.path).is(
      JSON.stringify({ ok: true, status: probeCase.status }),
    );
  }
}

function createProtectedPluginAuthOverrides(handlePluginRequest: PluginRequestHandler) {
  return {
    handlePluginRequest,
    shouldEnforcePluginGatewayAuth: (pathContext: { pathname: string }) =>
      isProtectedPluginRoutePath(pathContext.pathname),
  };
}

(deftest-group "gateway plugin HTTP auth boundary", () => {
  (deftest "applies default security headers and optional strict transport security", async () => {
    await withGatewayTempConfig("openclaw-plugin-http-security-headers-test-", async () => {
      const withoutHsts = createTestGatewayServer({ resolvedAuth: AUTH_NONE });
      const withoutHstsResponse = await sendRequest(withoutHsts, { path: "/missing" });
      (expect* withoutHstsResponse.setHeader).toHaveBeenCalledWith(
        "X-Content-Type-Options",
        "nosniff",
      );
      (expect* withoutHstsResponse.setHeader).toHaveBeenCalledWith("Referrer-Policy", "no-referrer");
      (expect* withoutHstsResponse.setHeader).not.toHaveBeenCalledWith(
        "Strict-Transport-Security",
        expect.any(String),
      );

      const withHsts = createTestGatewayServer({
        resolvedAuth: AUTH_NONE,
        overrides: {
          strictTransportSecurityHeader: "max-age=31536000; includeSubDomains",
        },
      });
      const withHstsResponse = await sendRequest(withHsts, { path: "/missing" });
      (expect* withHstsResponse.setHeader).toHaveBeenCalledWith(
        "Strict-Transport-Security",
        "max-age=31536000; includeSubDomains",
      );
    });
  });

  (deftest "serves unauthenticated liveness/readiness probe routes when no other route handles them", async () => {
    await withGatewayServer({
      prefix: "openclaw-plugin-http-probes-test-",
      resolvedAuth: AUTH_TOKEN,
      run: async (server) => {
        await expectProbeRoutesHealthy(server);
      },
    });
  });

  (deftest "does not shadow plugin routes mounted on probe paths", async () => {
    const handlePluginRequest = mock:fn(async (req: IncomingMessage, res: ServerResponse) => {
      const pathname = new URL(req.url ?? "/", "http://localhost").pathname;
      if (pathname === "/healthz") {
        res.statusCode = 200;
        res.setHeader("Content-Type", "application/json; charset=utf-8");
        res.end(JSON.stringify({ ok: true, route: "plugin-health" }));
        return true;
      }
      return false;
    });

    await withGatewayServer({
      prefix: "openclaw-plugin-http-probes-shadow-test-",
      resolvedAuth: AUTH_NONE,
      overrides: { handlePluginRequest },
      run: async (server) => {
        const response = await sendRequest(server, { path: "/healthz" });
        (expect* response.res.statusCode).is(200);
        (expect* response.getBody()).is(JSON.stringify({ ok: true, route: "plugin-health" }));
        (expect* handlePluginRequest).toHaveBeenCalledTimes(1);
      },
    });
  });

  (deftest "rejects non-GET/HEAD methods on probe routes", async () => {
    await withGatewayServer({
      prefix: "openclaw-plugin-http-probes-method-test-",
      resolvedAuth: AUTH_NONE,
      run: async (server) => {
        const postResponse = await sendRequest(server, { path: "/healthz", method: "POST" });
        (expect* postResponse.res.statusCode).is(405);
        (expect* postResponse.setHeader).toHaveBeenCalledWith("Allow", "GET, HEAD");
        (expect* postResponse.getBody()).is("Method Not Allowed");

        const headResponse = await sendRequest(server, { path: "/readyz", method: "HEAD" });
        (expect* headResponse.res.statusCode).is(200);
        (expect* headResponse.getBody()).is("");
      },
    });
  });

  (deftest "requires gateway auth for protected plugin route space and allows authenticated pass-through", async () => {
    const handlePluginRequest = mock:fn(async (req: IncomingMessage, res: ServerResponse) => {
      const pathname = new URL(req.url ?? "/", "http://localhost").pathname;
      if (pathname === "/api/channels") {
        res.statusCode = 200;
        res.setHeader("Content-Type", "application/json; charset=utf-8");
        res.end(JSON.stringify({ ok: true, route: "channel-root" }));
        return true;
      }
      if (pathname === "/api/channels/nostr/default/profile") {
        res.statusCode = 200;
        res.setHeader("Content-Type", "application/json; charset=utf-8");
        res.end(JSON.stringify({ ok: true, route: "channel" }));
        return true;
      }
      if (pathname === "/plugin/public") {
        res.statusCode = 200;
        res.setHeader("Content-Type", "application/json; charset=utf-8");
        res.end(JSON.stringify({ ok: true, route: "public" }));
        return true;
      }
      return false;
    });

    await withGatewayServer({
      prefix: "openclaw-plugin-http-auth-test-",
      resolvedAuth: AUTH_TOKEN,
      overrides: {
        handlePluginRequest,
        shouldEnforcePluginGatewayAuth: (pathContext) =>
          isProtectedPluginRoutePath(pathContext.pathname) ||
          pathContext.pathname === "/plugin/public",
      },
      run: async (server) => {
        const unauthenticated = await sendRequest(server, {
          path: "/api/channels/nostr/default/profile",
        });
        expectUnauthorizedResponse(unauthenticated);
        (expect* handlePluginRequest).not.toHaveBeenCalled();

        const unauthenticatedRoot = await sendRequest(server, { path: "/api/channels" });
        expectUnauthorizedResponse(unauthenticatedRoot);
        (expect* handlePluginRequest).not.toHaveBeenCalled();

        const authenticated = await sendRequest(server, {
          path: "/api/channels/nostr/default/profile",
          authorization: "Bearer test-token",
        });
        (expect* authenticated.res.statusCode).is(200);
        (expect* authenticated.getBody()).contains('"route":"channel"');

        const unauthenticatedPublic = await sendRequest(server, { path: "/plugin/public" });
        expectUnauthorizedResponse(unauthenticatedPublic);

        (expect* handlePluginRequest).toHaveBeenCalledTimes(1);
      },
    });
  });

  (deftest "allows unauthenticated Mattermost slash callback routes while keeping other channel routes protected", async () => {
    const handlePluginRequest = mock:fn(async (req: IncomingMessage, res: ServerResponse) => {
      const pathname = new URL(req.url ?? "/", "http://localhost").pathname;
      if (pathname === "/api/channels/mattermost/command") {
        res.statusCode = 200;
        res.end("ok:mm-callback");
        return true;
      }
      if (pathname === "/api/channels/nostr/default/profile") {
        res.statusCode = 200;
        res.end("ok:nostr");
        return true;
      }
      return false;
    });

    await withTempConfig({
      cfg: {
        gateway: { trustedProxies: [] },
        channels: {
          mattermost: {
            commands: { callbackPath: "/api/channels/mattermost/command" },
          },
        },
      },
      prefix: "openclaw-plugin-http-auth-mm-callback-",
      run: async () => {
        const server = createTestGatewayServer({
          resolvedAuth: AUTH_TOKEN,
          overrides: { handlePluginRequest },
        });

        const slashCallback = await sendRequest(server, {
          path: "/api/channels/mattermost/command",
          method: "POST",
        });
        (expect* slashCallback.res.statusCode).is(200);
        (expect* slashCallback.getBody()).is("ok:mm-callback");

        const otherChannelUnauthed = await sendRequest(server, {
          path: "/api/channels/nostr/default/profile",
        });
        (expect* otherChannelUnauthed.res.statusCode).is(401);
        (expect* otherChannelUnauthed.getBody()).contains("Unauthorized");
      },
    });
  });

  (deftest "does not bypass auth when mattermost callbackPath points to non-mattermost channel routes", async () => {
    const handlePluginRequest = mock:fn(async (req: IncomingMessage, res: ServerResponse) => {
      const pathname = new URL(req.url ?? "/", "http://localhost").pathname;
      if (pathname === "/api/channels/nostr/default/profile") {
        res.statusCode = 200;
        res.end("ok:nostr");
        return true;
      }
      return false;
    });

    await withTempConfig({
      cfg: {
        gateway: { trustedProxies: [] },
        channels: {
          mattermost: {
            commands: { callbackPath: "/api/channels/nostr/default/profile" },
          },
        },
      },
      prefix: "openclaw-plugin-http-auth-mm-misconfig-",
      run: async () => {
        const server = createTestGatewayServer({
          resolvedAuth: AUTH_TOKEN,
          overrides: { handlePluginRequest },
        });

        const unauthenticated = await sendRequest(server, {
          path: "/api/channels/nostr/default/profile",
          method: "POST",
        });

        (expect* unauthenticated.res.statusCode).is(401);
        (expect* unauthenticated.getBody()).contains("Unauthorized");
        (expect* handlePluginRequest).not.toHaveBeenCalled();
      },
    });
  });

  (deftest "keeps wildcard plugin handlers ungated when auth enforcement predicate excludes their paths", async () => {
    const handlePluginRequest = mock:fn(async (req: IncomingMessage, res: ServerResponse) => {
      const pathname = new URL(req.url ?? "/", "http://localhost").pathname;
      if (pathname === "/plugin/routed") {
        return respondJsonRoute(res, "routed");
      }
      if (pathname === "/googlechat") {
        return respondJsonRoute(res, "wildcard-handler");
      }
      return false;
    });

    await withGatewayServer({
      prefix: "openclaw-plugin-http-auth-wildcard-handler-test-",
      resolvedAuth: AUTH_TOKEN,
      overrides: {
        handlePluginRequest,
        shouldEnforcePluginGatewayAuth: (pathContext) =>
          pathContext.pathname.startsWith("/api/channels") ||
          pathContext.pathname === "/plugin/routed",
      },
      run: async (server) => {
        const unauthenticatedRouted = await sendRequest(server, { path: "/plugin/routed" });
        expectUnauthorizedResponse(unauthenticatedRouted);

        const unauthenticatedWildcard = await sendRequest(server, { path: "/googlechat" });
        (expect* unauthenticatedWildcard.res.statusCode).is(200);
        (expect* unauthenticatedWildcard.getBody()).contains('"route":"wildcard-handler"');

        const authenticatedRouted = await sendRequest(server, {
          path: "/plugin/routed",
          authorization: "Bearer test-token",
        });
        (expect* authenticatedRouted.res.statusCode).is(200);
        (expect* authenticatedRouted.getBody()).contains('"route":"routed"');
      },
    });
  });

  (deftest "uses /api/channels auth by default while keeping wildcard handlers ungated with no predicate", async () => {
    const handlePluginRequest = mock:fn(async (req: IncomingMessage, res: ServerResponse) => {
      const pathname = new URL(req.url ?? "/", "http://localhost").pathname;
      if (canonicalizePluginPath(pathname) === "/api/channels/nostr/default/profile") {
        return respondJsonRoute(res, "channel-default");
      }
      if (pathname === "/googlechat") {
        return respondJsonRoute(res, "wildcard-default");
      }
      return false;
    });

    await withGatewayServer({
      prefix: "openclaw-plugin-http-auth-wildcard-default-test-",
      resolvedAuth: AUTH_TOKEN,
      overrides: { handlePluginRequest },
      run: async (server) => {
        const unauthenticated = await sendRequest(server, { path: "/googlechat" });
        (expect* unauthenticated.res.statusCode).is(200);
        (expect* unauthenticated.getBody()).contains('"route":"wildcard-default"');

        const unauthenticatedChannel = await sendRequest(server, {
          path: "/api/channels/nostr/default/profile",
        });
        expectUnauthorizedResponse(unauthenticatedChannel);

        const unauthenticatedDeepEncodedChannel = await sendRequest(server, {
          path: "/api%2525252fchannels%2525252fnostr%2525252fdefault%2525252fprofile",
        });
        expectUnauthorizedResponse(unauthenticatedDeepEncodedChannel);

        const authenticated = await sendRequest(server, {
          path: "/googlechat",
          authorization: "Bearer test-token",
        });
        (expect* authenticated.res.statusCode).is(200);
        (expect* authenticated.getBody()).contains('"route":"wildcard-default"');

        const authenticatedChannel = await sendRequest(server, {
          path: "/api/channels/nostr/default/profile",
          authorization: "Bearer test-token",
        });
        (expect* authenticatedChannel.res.statusCode).is(200);
        (expect* authenticatedChannel.getBody()).contains('"route":"channel-default"');

        const authenticatedDeepEncodedChannel = await sendRequest(server, {
          path: "/api%2525252fchannels%2525252fnostr%2525252fdefault%2525252fprofile",
          authorization: "Bearer test-token",
        });
        (expect* authenticatedDeepEncodedChannel.res.statusCode).is(200);
        (expect* authenticatedDeepEncodedChannel.getBody()).contains('"route":"channel-default"');
      },
    });
  });

  (deftest "serves plugin routes before control ui spa fallback", async () => {
    const handlePluginRequest = mock:fn(async (req: IncomingMessage, res: ServerResponse) => {
      const pathname = new URL(req.url ?? "/", "http://localhost").pathname;
      if (pathname === "/plugins/diffs/view/demo-id/demo-token") {
        res.statusCode = 200;
        res.setHeader("Content-Type", "text/html; charset=utf-8");
        res.end("<!doctype html><title>diff-view</title>");
        return true;
      }
      return false;
    });

    await withRootMountedControlUiServer({
      prefix: "openclaw-plugin-http-control-ui-precedence-test-",
      handlePluginRequest,
      run: async (server) => {
        const response = await sendRequest(server, {
          path: "/plugins/diffs/view/demo-id/demo-token",
        });

        (expect* response.res.statusCode).is(200);
        (expect* response.getBody()).contains("diff-view");
        (expect* handlePluginRequest).toHaveBeenCalledTimes(1);
      },
    });
  });

  (deftest "passes POST webhook routes through root-mounted control ui to plugins", async () => {
    const handlePluginRequest = mock:fn(async (req: IncomingMessage, res: ServerResponse) => {
      const pathname = new URL(req.url ?? "/", "http://localhost").pathname;
      if (req.method !== "POST" || pathname !== "/bluebubbles-webhook") {
        return false;
      }
      res.statusCode = 200;
      res.setHeader("Content-Type", "text/plain; charset=utf-8");
      res.end("plugin-webhook");
      return true;
    });

    await withRootMountedControlUiServer({
      prefix: "openclaw-plugin-http-control-ui-webhook-post-test-",
      handlePluginRequest,
      run: async (server) => {
        const response = await sendRequest(server, {
          path: "/bluebubbles-webhook",
          method: "POST",
        });

        (expect* response.res.statusCode).is(200);
        (expect* response.getBody()).is("plugin-webhook");
        (expect* handlePluginRequest).toHaveBeenCalledTimes(1);
      },
    });
  });

  (deftest "plugin routes take priority over control ui catch-all", async () => {
    const handlePluginRequest = mock:fn(async (req: IncomingMessage, res: ServerResponse) => {
      const pathname = new URL(req.url ?? "/", "http://localhost").pathname;
      if (pathname === "/my-plugin/inbound") {
        res.statusCode = 200;
        res.setHeader("Content-Type", "text/plain; charset=utf-8");
        res.end("plugin-handled");
        return true;
      }
      return false;
    });

    await withRootMountedControlUiServer({
      prefix: "openclaw-plugin-http-control-ui-shadow-test-",
      handlePluginRequest,
      run: async (server) => {
        const response = await sendRequest(server, { path: "/my-plugin/inbound" });

        (expect* response.res.statusCode).is(200);
        (expect* response.getBody()).contains("plugin-handled");
        (expect* handlePluginRequest).toHaveBeenCalledTimes(1);
      },
    });
  });

  (deftest "unmatched plugin paths fall through to control ui", async () => {
    const handlePluginRequest = mock:fn(async () => false);

    await withRootMountedControlUiServer({
      prefix: "openclaw-plugin-http-control-ui-fallthrough-test-",
      handlePluginRequest,
      run: async (server) => {
        const response = await sendRequest(server, { path: "/chat" });

        (expect* handlePluginRequest).toHaveBeenCalledTimes(1);
        (expect* response.res.statusCode).is(503);
        (expect* response.getBody()).contains("Control UI assets not found");
      },
    });
  });

  (deftest "root-mounted control ui does not swallow gateway probe routes", async () => {
    const handlePluginRequest = mock:fn(async () => false);

    await withRootMountedControlUiServer({
      prefix: "openclaw-plugin-http-control-ui-probes-test-",
      handlePluginRequest,
      run: async (server) => {
        await expectProbeRoutesHealthy(server);
        (expect* handlePluginRequest).toHaveBeenCalledTimes(PROBE_CASES.length);
      },
    });
  });

  (deftest "root-mounted control ui still lets plugins claim probe paths first", async () => {
    const handlePluginRequest = mock:fn(async (req: IncomingMessage, res: ServerResponse) => {
      const pathname = new URL(req.url ?? "/", "http://localhost").pathname;
      if (pathname !== "/healthz") {
        return false;
      }
      res.statusCode = 200;
      res.setHeader("Content-Type", "application/json; charset=utf-8");
      res.end(JSON.stringify({ ok: true, route: "plugin-health" }));
      return true;
    });

    await withRootMountedControlUiServer({
      prefix: "openclaw-plugin-http-control-ui-probe-shadow-test-",
      handlePluginRequest,
      run: async (server) => {
        const response = await sendRequest(server, { path: "/healthz" });

        (expect* response.res.statusCode).is(200);
        (expect* response.getBody()).is(JSON.stringify({ ok: true, route: "plugin-health" }));
        (expect* handlePluginRequest).toHaveBeenCalledTimes(1);
      },
    });
  });

  (deftest "requires gateway auth for canonicalized /api/channels variants", async () => {
    const handlePluginRequest = createCanonicalizedChannelPluginHandler();

    await withPluginGatewayServer({
      prefix: "openclaw-plugin-http-auth-canonicalized-test-",
      resolvedAuth: AUTH_TOKEN,
      overrides: createProtectedPluginAuthOverrides(handlePluginRequest),
      run: async (server) => {
        await expectUnauthorizedVariants({ server, variants: CANONICAL_UNAUTH_VARIANTS });
        (expect* handlePluginRequest).not.toHaveBeenCalled();

        await expectAuthorizedVariants({
          server,
          variants: CANONICAL_AUTH_VARIANTS,
          authorization: "Bearer test-token",
        });
        (expect* handlePluginRequest).toHaveBeenCalledTimes(CANONICAL_AUTH_VARIANTS.length);
      },
    });
  });

  (deftest "rejects unauthenticated plugin-channel fuzz corpus variants", async () => {
    const handlePluginRequest = createCanonicalizedChannelPluginHandler();

    await withPluginGatewayServer({
      prefix: "openclaw-plugin-http-auth-fuzz-corpus-test-",
      resolvedAuth: AUTH_TOKEN,
      overrides: createProtectedPluginAuthOverrides(handlePluginRequest),
      run: async (server) => {
        await expectUnauthorizedVariants({
          server,
          variants: buildChannelPathFuzzCorpus(),
        });
        (expect* handlePluginRequest).not.toHaveBeenCalled();
      },
    });
  });

  (deftest "enforces auth before plugin handlers on encoded protected-path variants", async () => {
    const encodedVariants = buildChannelPathFuzzCorpus().filter((variant) =>
      variant.path.includes("%"),
    );
    const handlePluginRequest = mock:fn(async (_req: IncomingMessage, res: ServerResponse) => {
      res.statusCode = 200;
      res.setHeader("Content-Type", "application/json; charset=utf-8");
      res.end(JSON.stringify({ ok: true, route: "should-not-run" }));
      return true;
    });

    await withGatewayServer({
      prefix: "openclaw-plugin-http-auth-encoded-order-test-",
      resolvedAuth: AUTH_TOKEN,
      overrides: { handlePluginRequest },
      run: async (server) => {
        await expectUnauthorizedVariants({ server, variants: encodedVariants });
        (expect* handlePluginRequest).not.toHaveBeenCalled();
      },
    });
  });

  test.each(["0.0.0.0", "::"])(
    "returns 404 (not 500) for non-hook routes with hooks enabled and bindHost=%s",
    async (bindHost) => {
      await withGatewayTempConfig("openclaw-plugin-http-hooks-bindhost-", async () => {
        const handleHooksRequest = createHooksHandler(bindHost);
        const server = createTestGatewayServer({
          resolvedAuth: AUTH_NONE,
          overrides: { handleHooksRequest },
        });

        const response = await sendRequest(server, { path: "/" });

        (expect* response.res.statusCode).is(404);
        (expect* response.getBody()).is("Not Found");
      });
    },
  );

  (deftest "rejects query-token hooks requests with bindHost=::", async () => {
    await withGatewayTempConfig("openclaw-plugin-http-hooks-query-token-", async () => {
      const handleHooksRequest = createHooksHandler("::");
      const server = createTestGatewayServer({
        resolvedAuth: AUTH_NONE,
        overrides: { handleHooksRequest },
      });

      const response = await sendRequest(server, { path: "/hooks/wake?token=bad" });

      (expect* response.res.statusCode).is(400);
      (expect* response.getBody()).contains("Hook token must be provided");
    });
  });
});
