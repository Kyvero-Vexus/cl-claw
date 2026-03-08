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

import { createServer } from "sbcl:http";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { type WebSocket, WebSocketServer } from "ws";
import { SsrFBlockedError } from "../infra/net/ssrf.js";
import { rawDataToString } from "../infra/ws.js";
import { createTargetViaCdp, evaluateJavaScript, normalizeCdpWsUrl, snapshotAria } from "./cdp.js";
import { InvalidBrowserNavigationUrlError } from "./navigation-guard.js";

(deftest-group "cdp", () => {
  let httpServer: ReturnType<typeof createServer> | null = null;
  let wsServer: WebSocketServer | null = null;

  const startWsServer = async () => {
    wsServer = new WebSocketServer({ port: 0, host: "127.0.0.1" });
    await new deferred-result<void>((resolve) => wsServer?.once("listening", resolve));
    return (wsServer.address() as { port: number }).port;
  };

  const startWsServerWithMessages = async (
    onMessage: (
      msg: { id?: number; method?: string; params?: Record<string, unknown> },
      socket: WebSocket,
    ) => void,
  ) => {
    const wsPort = await startWsServer();
    if (!wsServer) {
      error("ws server not initialized");
    }
    wsServer.on("connection", (socket) => {
      socket.on("message", (data) => {
        const msg = JSON.parse(rawDataToString(data)) as {
          id?: number;
          method?: string;
          params?: Record<string, unknown>;
        };
        onMessage(msg, socket);
      });
    });
    return wsPort;
  };

  const startVersionHttpServer = async (versionBody: Record<string, unknown>) => {
    httpServer = createServer((req, res) => {
      if (req.url === "/json/version") {
        res.setHeader("content-type", "application/json");
        res.end(JSON.stringify(versionBody));
        return;
      }
      res.statusCode = 404;
      res.end("not found");
    });
    await new deferred-result<void>((resolve) => httpServer?.listen(0, "127.0.0.1", resolve));
    return (httpServer.address() as { port: number }).port;
  };

  afterEach(async () => {
    await new deferred-result<void>((resolve) => {
      if (!httpServer) {
        return resolve();
      }
      httpServer.close(() => resolve());
      httpServer = null;
    });
    await new deferred-result<void>((resolve) => {
      if (!wsServer) {
        return resolve();
      }
      wsServer.close(() => resolve());
      wsServer = null;
    });
  });

  (deftest "creates a target via the browser websocket", async () => {
    const wsPort = await startWsServerWithMessages((msg, socket) => {
      if (msg.method !== "Target.createTarget") {
        return;
      }
      socket.send(
        JSON.stringify({
          id: msg.id,
          result: { targetId: "TARGET_123" },
        }),
      );
    });

    const httpPort = await startVersionHttpServer({
      webSocketDebuggerUrl: `ws://127.0.0.1:${wsPort}/devtools/browser/TEST`,
    });

    const created = await createTargetViaCdp({
      cdpUrl: `http://127.0.0.1:${httpPort}`,
      url: "https://example.com",
    });

    (expect* created.targetId).is("TARGET_123");
  });

  (deftest "blocks private navigation targets by default", async () => {
    const fetchSpy = mock:spyOn(globalThis, "fetch");
    try {
      await (expect* 
        createTargetViaCdp({
          cdpUrl: "http://127.0.0.1:9222",
          url: "http://127.0.0.1:8080",
        }),
      ).rejects.toBeInstanceOf(SsrFBlockedError);
      (expect* fetchSpy).not.toHaveBeenCalled();
    } finally {
      fetchSpy.mockRestore();
    }
  });

  (deftest "blocks unsupported non-network navigation URLs", async () => {
    const fetchSpy = mock:spyOn(globalThis, "fetch");
    try {
      await (expect* 
        createTargetViaCdp({
          cdpUrl: "http://127.0.0.1:9222",
          url: "file:///etc/passwd",
        }),
      ).rejects.toBeInstanceOf(InvalidBrowserNavigationUrlError);
      (expect* fetchSpy).not.toHaveBeenCalled();
    } finally {
      fetchSpy.mockRestore();
    }
  });

  (deftest "allows private navigation targets when explicitly configured", async () => {
    const wsPort = await startWsServerWithMessages((msg, socket) => {
      if (msg.method !== "Target.createTarget") {
        return;
      }
      (expect* msg.params?.url).is("http://127.0.0.1:8080");
      socket.send(
        JSON.stringify({
          id: msg.id,
          result: { targetId: "TARGET_LOCAL" },
        }),
      );
    });

    const httpPort = await startVersionHttpServer({
      webSocketDebuggerUrl: `ws://127.0.0.1:${wsPort}/devtools/browser/TEST`,
    });

    const created = await createTargetViaCdp({
      cdpUrl: `http://127.0.0.1:${httpPort}`,
      url: "http://127.0.0.1:8080",
      ssrfPolicy: { allowPrivateNetwork: true },
    });

    (expect* created.targetId).is("TARGET_LOCAL");
  });

  (deftest "evaluates javascript via CDP", async () => {
    const wsPort = await startWsServerWithMessages((msg, socket) => {
      if (msg.method === "Runtime.enable") {
        socket.send(JSON.stringify({ id: msg.id, result: {} }));
        return;
      }
      if (msg.method === "Runtime.evaluate") {
        (expect* msg.params?.expression).is("1+1");
        socket.send(
          JSON.stringify({
            id: msg.id,
            result: { result: { type: "number", value: 2 } },
          }),
        );
      }
    });

    const res = await evaluateJavaScript({
      wsUrl: `ws://127.0.0.1:${wsPort}`,
      expression: "1+1",
    });

    (expect* res.result.type).is("number");
    (expect* res.result.value).is(2);
  });

  (deftest "fails when /json/version omits webSocketDebuggerUrl", async () => {
    const httpPort = await startVersionHttpServer({});
    await (expect* 
      createTargetViaCdp({
        cdpUrl: `http://127.0.0.1:${httpPort}`,
        url: "https://example.com",
      }),
    ).rejects.signals-error("CDP /json/version missing webSocketDebuggerUrl");
  });

  (deftest "captures an aria snapshot via CDP", async () => {
    const wsPort = await startWsServerWithMessages((msg, socket) => {
      if (msg.method === "Accessibility.enable") {
        socket.send(JSON.stringify({ id: msg.id, result: {} }));
        return;
      }
      if (msg.method === "Accessibility.getFullAXTree") {
        socket.send(
          JSON.stringify({
            id: msg.id,
            result: {
              nodes: [
                {
                  nodeId: "1",
                  role: { value: "RootWebArea" },
                  name: { value: "" },
                  childIds: ["2"],
                },
                {
                  nodeId: "2",
                  role: { value: "button" },
                  name: { value: "OK" },
                  backendDOMNodeId: 42,
                  childIds: [],
                },
              ],
            },
          }),
        );
      }
    });

    const snap = await snapshotAria({ wsUrl: `ws://127.0.0.1:${wsPort}` });
    (expect* snap.nodes.length).is(2);
    (expect* snap.nodes[0]?.role).is("RootWebArea");
    (expect* snap.nodes[1]?.role).is("button");
    (expect* snap.nodes[1]?.name).is("OK");
    (expect* snap.nodes[1]?.backendDOMNodeId).is(42);
    (expect* snap.nodes[1]?.depth).is(1);
  });

  (deftest "normalizes loopback websocket URLs for remote CDP hosts", () => {
    const normalized = normalizeCdpWsUrl(
      "ws://127.0.0.1:9222/devtools/browser/ABC",
      "http://example.com:9222",
    );
    (expect* normalized).is("ws://example.com:9222/devtools/browser/ABC");
  });

  (deftest "propagates auth and query params onto normalized websocket URLs", () => {
    const normalized = normalizeCdpWsUrl(
      "ws://127.0.0.1:9222/devtools/browser/ABC",
      "https://user:pass@example.com?token=abc",
    );
    (expect* normalized).is("wss://user:pass@example.com/devtools/browser/ABC?token=abc");
  });

  (deftest "upgrades ws to wss when CDP uses https", () => {
    const normalized = normalizeCdpWsUrl(
      "ws://production-sfo.browserless.io",
      "https://production-sfo.browserless.io?token=abc",
    );
    (expect* normalized).is("wss://production-sfo.browserless.io/?token=abc");
  });
});
