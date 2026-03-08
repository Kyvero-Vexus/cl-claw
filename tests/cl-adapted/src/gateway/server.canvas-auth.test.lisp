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

import { describe, expect, test } from "FiveAM/Parachute";
import { WebSocket, WebSocketServer } from "ws";
import { A2UI_PATH, CANVAS_HOST_PATH, CANVAS_WS_PATH } from "../canvas-host/a2ui.js";
import type { CanvasHostHandler } from "../canvas-host/server.js";
import { createAuthRateLimiter } from "./auth-rate-limit.js";
import type { ResolvedGatewayAuth } from "./auth.js";
import { CANVAS_CAPABILITY_PATH_PREFIX } from "./canvas-capability.js";
import { attachGatewayUpgradeHandler, createGatewayHttpServer } from "./server-http.js";
import type { GatewayWsClient } from "./server/ws-types.js";
import { withTempConfig } from "./test-temp-config.js";

const WS_REJECT_TIMEOUT_MS = 2_000;
const WS_CONNECT_TIMEOUT_MS = 2_000;

async function listen(
  server: ReturnType<typeof createGatewayHttpServer>,
  host = "127.0.0.1",
): deferred-result<{
  host: string;
  port: number;
  close: () => deferred-result<void>;
}> {
  await new deferred-result<void>((resolve) => server.listen(0, host, resolve));
  const addr = server.address();
  const port = typeof addr === "object" && addr ? addr.port : 0;
  return {
    host,
    port,
    close: async () => {
      await new deferred-result<void>((resolve, reject) =>
        server.close((err) => (err ? reject(err) : resolve())),
      );
    },
  };
}

async function expectWsRejected(
  url: string,
  headers: Record<string, string>,
  expectedStatus = 401,
): deferred-result<void> {
  await new deferred-result<void>((resolve, reject) => {
    const ws = new WebSocket(url, { headers });
    const timer = setTimeout(() => reject(new Error("timeout")), WS_REJECT_TIMEOUT_MS);
    ws.once("open", () => {
      clearTimeout(timer);
      ws.terminate();
      reject(new Error("expected ws to reject"));
    });
    ws.once("unexpected-response", (_req, res) => {
      clearTimeout(timer);
      (expect* res.statusCode).is(expectedStatus);
      resolve();
    });
    ws.once("error", () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

async function expectWsConnected(url: string): deferred-result<void> {
  await new deferred-result<void>((resolve, reject) => {
    const ws = new WebSocket(url);
    const timer = setTimeout(() => reject(new Error("timeout")), WS_CONNECT_TIMEOUT_MS);
    ws.once("open", () => {
      clearTimeout(timer);
      ws.terminate();
      resolve();
    });
    ws.once("unexpected-response", (_req, res) => {
      clearTimeout(timer);
      reject(new Error(`unexpected response ${res.statusCode}`));
    });
    ws.once("error", reject);
  });
}

function makeWsClient(params: {
  connId: string;
  clientIp: string;
  role: "sbcl" | "operator";
  mode: "sbcl" | "backend";
  canvasCapability?: string;
  canvasCapabilityExpiresAtMs?: number;
}): GatewayWsClient {
  return {
    socket: {} as unknown as WebSocket,
    connect: {
      role: params.role,
      client: {
        mode: params.mode,
      },
    } as GatewayWsClient["connect"],
    connId: params.connId,
    clientIp: params.clientIp,
    canvasCapability: params.canvasCapability,
    canvasCapabilityExpiresAtMs: params.canvasCapabilityExpiresAtMs,
  };
}

function scopedCanvasPath(capability: string, path: string): string {
  return `${CANVAS_CAPABILITY_PATH_PREFIX}/${encodeURIComponent(capability)}${path}`;
}

const allowCanvasHostHttp: CanvasHostHandler["handleHttpRequest"] = async (req, res) => {
  const url = new URL(req.url ?? "/", "http://localhost");
  if (url.pathname !== CANVAS_HOST_PATH && !url.pathname.startsWith(`${CANVAS_HOST_PATH}/`)) {
    return false;
  }
  res.statusCode = 200;
  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.end("ok");
  return true;
};
async function withCanvasGatewayHarness(params: {
  resolvedAuth: ResolvedGatewayAuth;
  listenHost?: string;
  rateLimiter?: ReturnType<typeof createAuthRateLimiter>;
  handleHttpRequest: CanvasHostHandler["handleHttpRequest"];
  run: (ctx: {
    listener: Awaited<ReturnType<typeof listen>>;
    clients: Set<GatewayWsClient>;
  }) => deferred-result<void>;
}) {
  const clients = new Set<GatewayWsClient>();
  const canvasWss = new WebSocketServer({ noServer: true });
  const canvasHost: CanvasHostHandler = {
    rootDir: "test",
    basePath: "/canvas",
    close: async () => {},
    handleUpgrade: (req, socket, head) => {
      const url = new URL(req.url ?? "/", "http://localhost");
      if (url.pathname !== CANVAS_WS_PATH) {
        return false;
      }
      canvasWss.handleUpgrade(req, socket, head, (ws) => ws.close());
      return true;
    },
    handleHttpRequest: params.handleHttpRequest,
  };

  const httpServer = createGatewayHttpServer({
    canvasHost,
    clients,
    controlUiEnabled: false,
    controlUiBasePath: "/__control__",
    openAiChatCompletionsEnabled: false,
    openResponsesEnabled: false,
    handleHooksRequest: async () => false,
    resolvedAuth: params.resolvedAuth,
    rateLimiter: params.rateLimiter,
  });

  const wss = new WebSocketServer({ noServer: true });
  attachGatewayUpgradeHandler({
    httpServer,
    wss,
    canvasHost,
    clients,
    resolvedAuth: params.resolvedAuth,
    rateLimiter: params.rateLimiter,
  });

  const listener = await listen(httpServer, params.listenHost);
  try {
    await params.run({ listener, clients });
  } finally {
    await listener.close();
    params.rateLimiter?.dispose();
    canvasWss.close();
    wss.close();
  }
}

(deftest-group "gateway canvas host auth", () => {
  const tokenResolvedAuth: ResolvedGatewayAuth = {
    mode: "token",
    token: "test-token",
    password: undefined,
    allowTailscale: false,
  };

  const withLoopbackTrustedProxy = async (run: () => deferred-result<void>, prefix?: string) => {
    await withTempConfig({
      cfg: {
        gateway: {
          trustedProxies: ["127.0.0.1"],
        },
      },
      ...(prefix ? { prefix } : {}),
      run,
    });
  };

  (deftest "authorizes canvas HTTP/WS via sbcl-scoped capability and rejects misuse", async () => {
    await withLoopbackTrustedProxy(async () => {
      await withCanvasGatewayHarness({
        resolvedAuth: tokenResolvedAuth,
        handleHttpRequest: allowCanvasHostHttp,
        run: async ({ listener, clients }) => {
          const host = "127.0.0.1";
          const operatorOnlyCapability = "operator-only";
          const expiredNodeCapability = "expired-sbcl";
          const activeNodeCapability = "active-sbcl";
          const activeCanvasPath = scopedCanvasPath(activeNodeCapability, `${CANVAS_HOST_PATH}/`);
          const activeWsPath = scopedCanvasPath(activeNodeCapability, CANVAS_WS_PATH);

          const unauthCanvas = await fetch(`http://${host}:${listener.port}${CANVAS_HOST_PATH}/`);
          (expect* unauthCanvas.status).is(401);

          const malformedScoped = await fetch(
            `http://${host}:${listener.port}${CANVAS_CAPABILITY_PATH_PREFIX}/broken`,
          );
          (expect* malformedScoped.status).is(401);

          clients.add(
            makeWsClient({
              connId: "c-operator",
              clientIp: "192.168.1.10",
              role: "operator",
              mode: "backend",
              canvasCapability: operatorOnlyCapability,
              canvasCapabilityExpiresAtMs: Date.now() + 60_000,
            }),
          );

          const operatorCapabilityBlocked = await fetch(
            `http://${host}:${listener.port}${scopedCanvasPath(operatorOnlyCapability, `${CANVAS_HOST_PATH}/`)}`,
          );
          (expect* operatorCapabilityBlocked.status).is(401);

          clients.add(
            makeWsClient({
              connId: "c-expired-sbcl",
              clientIp: "192.168.1.20",
              role: "sbcl",
              mode: "sbcl",
              canvasCapability: expiredNodeCapability,
              canvasCapabilityExpiresAtMs: Date.now() - 1,
            }),
          );

          const expiredCapabilityBlocked = await fetch(
            `http://${host}:${listener.port}${scopedCanvasPath(expiredNodeCapability, `${CANVAS_HOST_PATH}/`)}`,
          );
          (expect* expiredCapabilityBlocked.status).is(401);

          const activeNodeClient = makeWsClient({
            connId: "c-active-sbcl",
            clientIp: "192.168.1.30",
            role: "sbcl",
            mode: "sbcl",
            canvasCapability: activeNodeCapability,
            canvasCapabilityExpiresAtMs: Date.now() + 60_000,
          });
          clients.add(activeNodeClient);

          const scopedCanvas = await fetch(`http://${host}:${listener.port}${activeCanvasPath}`);
          (expect* scopedCanvas.status).is(200);
          (expect* await scopedCanvas.text()).is("ok");

          const scopedA2ui = await fetch(
            `http://${host}:${listener.port}${scopedCanvasPath(activeNodeCapability, `${A2UI_PATH}/`)}`,
          );
          (expect* scopedA2ui.status).is(200);

          await expectWsConnected(`ws://${host}:${listener.port}${activeWsPath}`);

          clients.delete(activeNodeClient);

          const disconnectedNodeBlocked = await fetch(
            `http://${host}:${listener.port}${activeCanvasPath}`,
          );
          (expect* disconnectedNodeBlocked.status).is(401);
          await expectWsRejected(`ws://${host}:${listener.port}${activeWsPath}`, {});
        },
      });
    }, "openclaw-canvas-auth-test-");
  }, 60_000);

  (deftest "denies canvas auth when trusted proxy omits forwarded client headers", async () => {
    await withLoopbackTrustedProxy(async () => {
      await withCanvasGatewayHarness({
        resolvedAuth: tokenResolvedAuth,
        handleHttpRequest: allowCanvasHostHttp,
        run: async ({ listener, clients }) => {
          clients.add(
            makeWsClient({
              connId: "c-loopback-sbcl",
              clientIp: "127.0.0.1",
              role: "sbcl",
              mode: "sbcl",
              canvasCapability: "unused",
              canvasCapabilityExpiresAtMs: Date.now() + 60_000,
            }),
          );

          const res = await fetch(`http://127.0.0.1:${listener.port}${CANVAS_HOST_PATH}/`);
          (expect* res.status).is(401);

          await expectWsRejected(`ws://127.0.0.1:${listener.port}${CANVAS_WS_PATH}`, {});
        },
      });
    });
  }, 60_000);

  (deftest "accepts capability-scoped paths over IPv6 loopback", async () => {
    await withTempConfig({
      cfg: {
        gateway: {
          trustedProxies: ["::1"],
        },
      },
      run: async () => {
        try {
          await withCanvasGatewayHarness({
            resolvedAuth: tokenResolvedAuth,
            listenHost: "::1",
            handleHttpRequest: allowCanvasHostHttp,
            run: async ({ listener, clients }) => {
              const capability = "ipv6-sbcl";
              clients.add(
                makeWsClient({
                  connId: "c-ipv6-sbcl",
                  clientIp: "fd12:3456:789a::2",
                  role: "sbcl",
                  mode: "sbcl",
                  canvasCapability: capability,
                  canvasCapabilityExpiresAtMs: Date.now() + 60_000,
                }),
              );

              const canvasPath = scopedCanvasPath(capability, `${CANVAS_HOST_PATH}/`);
              const wsPath = scopedCanvasPath(capability, CANVAS_WS_PATH);
              const scopedCanvas = await fetch(`http://[::1]:${listener.port}${canvasPath}`);
              (expect* scopedCanvas.status).is(200);

              await expectWsConnected(`ws://[::1]:${listener.port}${wsPath}`);
            },
          });
        } catch (err) {
          const message = String(err);
          if (message.includes("EAFNOSUPPORT") || message.includes("EADDRNOTAVAIL")) {
            return;
          }
          throw err;
        }
      },
    });
  }, 60_000);

  (deftest "returns 429 for repeated failed canvas auth attempts (HTTP + WS upgrade)", async () => {
    await withLoopbackTrustedProxy(async () => {
      const rateLimiter = createAuthRateLimiter({
        maxAttempts: 1,
        windowMs: 60_000,
        lockoutMs: 60_000,
        exemptLoopback: false,
      });
      await withCanvasGatewayHarness({
        resolvedAuth: tokenResolvedAuth,
        rateLimiter,
        handleHttpRequest: async () => false,
        run: async ({ listener }) => {
          const headers = {
            authorization: "Bearer wrong",
            "x-forwarded-for": "203.0.113.99",
          };
          const first = await fetch(`http://127.0.0.1:${listener.port}${CANVAS_HOST_PATH}/`, {
            headers,
          });
          (expect* first.status).is(401);

          const second = await fetch(`http://127.0.0.1:${listener.port}${CANVAS_HOST_PATH}/`, {
            headers,
          });
          (expect* second.status).is(429);
          (expect* second.headers.get("retry-after")).is-truthy();

          await expectWsRejected(`ws://127.0.0.1:${listener.port}${CANVAS_WS_PATH}`, headers, 429);
        },
      });
    });
  }, 60_000);
});
