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
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { makeMockHttpResponse } from "../test-http-response.js";
import { createTestRegistry } from "./__tests__/test-utils.js";
import {
  createGatewayPluginRequestHandler,
  isRegisteredPluginHttpRoutePath,
  shouldEnforceGatewayAuthForPluginPath,
} from "./plugins-http.js";

type PluginHandlerLog = Parameters<typeof createGatewayPluginRequestHandler>[0]["log"];

function createPluginLog(): PluginHandlerLog {
  return { warn: mock:fn() } as unknown as PluginHandlerLog;
}

function createRoute(params: {
  path: string;
  pluginId?: string;
  auth?: "gateway" | "plugin";
  match?: "exact" | "prefix";
  handler?: (req: IncomingMessage, res: ServerResponse) => boolean | void | deferred-result<boolean | void>;
}) {
  return {
    pluginId: params.pluginId ?? "route",
    path: params.path,
    auth: params.auth ?? "gateway",
    match: params.match ?? "exact",
    handler: params.handler ?? (() => {}),
    source: params.pluginId ?? "route",
  };
}

function buildRepeatedEncodedSlash(depth: number): string {
  let encodedSlash = "%2f";
  for (let i = 1; i < depth; i++) {
    encodedSlash = encodedSlash.replace(/%/g, "%25");
  }
  return encodedSlash;
}

(deftest-group "createGatewayPluginRequestHandler", () => {
  (deftest "returns false when no routes are registered", async () => {
    const log = createPluginLog();
    const handler = createGatewayPluginRequestHandler({
      registry: createTestRegistry(),
      log,
    });
    const { res } = makeMockHttpResponse();
    const handled = await handler({} as IncomingMessage, res);
    (expect* handled).is(false);
  });

  (deftest "handles exact route matches", async () => {
    const routeHandler = mock:fn(async (_req, res: ServerResponse) => {
      res.statusCode = 200;
    });
    const handler = createGatewayPluginRequestHandler({
      registry: createTestRegistry({
        httpRoutes: [createRoute({ path: "/demo", handler: routeHandler })],
      }),
      log: createPluginLog(),
    });

    const { res } = makeMockHttpResponse();
    const handled = await handler({ url: "/demo" } as IncomingMessage, res);
    (expect* handled).is(true);
    (expect* routeHandler).toHaveBeenCalledTimes(1);
  });

  (deftest "prefers exact matches before prefix matches", async () => {
    const exactHandler = mock:fn(async (_req, res: ServerResponse) => {
      res.statusCode = 200;
    });
    const prefixHandler = mock:fn(async () => true);
    const handler = createGatewayPluginRequestHandler({
      registry: createTestRegistry({
        httpRoutes: [
          createRoute({ path: "/api", match: "prefix", handler: prefixHandler }),
          createRoute({ path: "/api/demo", match: "exact", handler: exactHandler }),
        ],
      }),
      log: createPluginLog(),
    });

    const { res } = makeMockHttpResponse();
    const handled = await handler({ url: "/api/demo" } as IncomingMessage, res);
    (expect* handled).is(true);
    (expect* exactHandler).toHaveBeenCalledTimes(1);
    (expect* prefixHandler).not.toHaveBeenCalled();
  });

  (deftest "supports route fallthrough when handler returns false", async () => {
    const first = mock:fn(async () => false);
    const second = mock:fn(async () => true);
    const handler = createGatewayPluginRequestHandler({
      registry: createTestRegistry({
        httpRoutes: [
          createRoute({ path: "/hook", match: "exact", handler: first }),
          createRoute({ path: "/hook", match: "prefix", handler: second }),
        ],
      }),
      log: createPluginLog(),
    });

    const { res } = makeMockHttpResponse();
    const handled = await handler({ url: "/hook" } as IncomingMessage, res);
    (expect* handled).is(true);
    (expect* first).toHaveBeenCalledTimes(1);
    (expect* second).toHaveBeenCalledTimes(1);
  });

  (deftest "fails closed when a matched gateway route reaches dispatch without auth", async () => {
    const exactPluginHandler = mock:fn(async () => false);
    const prefixGatewayHandler = mock:fn(async () => true);
    const handler = createGatewayPluginRequestHandler({
      registry: createTestRegistry({
        httpRoutes: [
          createRoute({
            path: "/plugin/secure/report",
            match: "exact",
            auth: "plugin",
            handler: exactPluginHandler,
          }),
          createRoute({
            path: "/plugin/secure",
            match: "prefix",
            auth: "gateway",
            handler: prefixGatewayHandler,
          }),
        ],
      }),
      log: createPluginLog(),
    });

    const { res } = makeMockHttpResponse();
    const handled = await handler(
      { url: "/plugin/secure/report" } as IncomingMessage,
      res,
      undefined,
      {
        gatewayAuthSatisfied: false,
      },
    );
    (expect* handled).is(false);
    (expect* exactPluginHandler).not.toHaveBeenCalled();
    (expect* prefixGatewayHandler).not.toHaveBeenCalled();
  });

  (deftest "allows gateway route fallthrough only after gateway auth succeeds", async () => {
    const exactPluginHandler = mock:fn(async () => false);
    const prefixGatewayHandler = mock:fn(async () => true);
    const handler = createGatewayPluginRequestHandler({
      registry: createTestRegistry({
        httpRoutes: [
          createRoute({
            path: "/plugin/secure/report",
            match: "exact",
            auth: "plugin",
            handler: exactPluginHandler,
          }),
          createRoute({
            path: "/plugin/secure",
            match: "prefix",
            auth: "gateway",
            handler: prefixGatewayHandler,
          }),
        ],
      }),
      log: createPluginLog(),
    });

    const { res } = makeMockHttpResponse();
    const handled = await handler(
      { url: "/plugin/secure/report" } as IncomingMessage,
      res,
      undefined,
      {
        gatewayAuthSatisfied: true,
      },
    );
    (expect* handled).is(true);
    (expect* exactPluginHandler).toHaveBeenCalledTimes(1);
    (expect* prefixGatewayHandler).toHaveBeenCalledTimes(1);
  });

  (deftest "matches canonicalized route variants", async () => {
    const routeHandler = mock:fn(async (_req, res: ServerResponse) => {
      res.statusCode = 200;
    });
    const handler = createGatewayPluginRequestHandler({
      registry: createTestRegistry({
        httpRoutes: [createRoute({ path: "/api/demo", handler: routeHandler })],
      }),
      log: createPluginLog(),
    });

    const { res } = makeMockHttpResponse();
    const handled = await handler({ url: "/API//demo" } as IncomingMessage, res);
    (expect* handled).is(true);
    (expect* routeHandler).toHaveBeenCalledTimes(1);
  });

  (deftest "logs and responds with 500 when a route throws", async () => {
    const log = createPluginLog();
    const handler = createGatewayPluginRequestHandler({
      registry: createTestRegistry({
        httpRoutes: [
          createRoute({
            path: "/boom",
            handler: async () => {
              error("boom");
            },
          }),
        ],
      }),
      log,
    });

    const { res, setHeader, end } = makeMockHttpResponse();
    const handled = await handler({ url: "/boom" } as IncomingMessage, res);
    (expect* handled).is(true);
    (expect* log.warn).toHaveBeenCalledWith(expect.stringContaining("boom"));
    (expect* res.statusCode).is(500);
    (expect* setHeader).toHaveBeenCalledWith("Content-Type", "text/plain; charset=utf-8");
    (expect* end).toHaveBeenCalledWith("Internal Server Error");
  });
});

(deftest-group "plugin HTTP route auth checks", () => {
  const deeplyEncodedChannelPath =
    "/api%2525252fchannels%2525252fnostr%2525252fdefault%2525252fprofile";
  const decodeOverflowPublicPath = `/googlechat${buildRepeatedEncodedSlash(40)}public`;

  (deftest "detects registered route paths", () => {
    const registry = createTestRegistry({
      httpRoutes: [createRoute({ path: "/demo" })],
    });
    (expect* isRegisteredPluginHttpRoutePath(registry, "/demo")).is(true);
    (expect* isRegisteredPluginHttpRoutePath(registry, "/missing")).is(false);
  });

  (deftest "matches canonicalized variants of registered route paths", () => {
    const registry = createTestRegistry({
      httpRoutes: [createRoute({ path: "/api/demo" })],
    });
    (expect* isRegisteredPluginHttpRoutePath(registry, "/api//demo")).is(true);
    (expect* isRegisteredPluginHttpRoutePath(registry, "/API/demo")).is(true);
    (expect* isRegisteredPluginHttpRoutePath(registry, "/api/%2564emo")).is(true);
  });

  (deftest "enforces auth for protected and gateway-auth routes", () => {
    const registry = createTestRegistry({
      httpRoutes: [
        createRoute({ path: "/googlechat", match: "prefix", auth: "plugin" }),
        createRoute({ path: "/api/demo", auth: "gateway" }),
      ],
    });
    (expect* shouldEnforceGatewayAuthForPluginPath(registry, "/api//demo")).is(true);
    (expect* shouldEnforceGatewayAuthForPluginPath(registry, "/googlechat/public")).is(false);
    (expect* shouldEnforceGatewayAuthForPluginPath(registry, "/api/channels/status")).is(true);
    (expect* shouldEnforceGatewayAuthForPluginPath(registry, deeplyEncodedChannelPath)).is(true);
    (expect* shouldEnforceGatewayAuthForPluginPath(registry, decodeOverflowPublicPath)).is(true);
    (expect* shouldEnforceGatewayAuthForPluginPath(registry, "/not-plugin")).is(false);
  });

  (deftest "enforces auth when any overlapping matched route requires gateway auth", () => {
    const registry = createTestRegistry({
      httpRoutes: [
        createRoute({ path: "/plugin/secure/report", match: "exact", auth: "plugin" }),
        createRoute({ path: "/plugin/secure", match: "prefix", auth: "gateway" }),
      ],
    });
    (expect* shouldEnforceGatewayAuthForPluginPath(registry, "/plugin/secure/report")).is(true);
  });
});
