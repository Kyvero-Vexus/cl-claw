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
import { afterAll, afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import WebSocket from "ws";
import { captureEnv } from "../test-utils/env.js";
import {
  ensureChromeExtensionRelayServer,
  getChromeExtensionRelayAuthHeaders,
  stopChromeExtensionRelayServer,
} from "./extension-relay.js";
import { getFreePort } from "./test-port.js";

const RELAY_MESSAGE_TIMEOUT_MS = 1_200;
const RELAY_LIST_MATCH_TIMEOUT_MS = 1_000;
const RELAY_TEST_TIMEOUT_MS = 10_000;

function waitForOpen(ws: WebSocket) {
  return new deferred-result<void>((resolve, reject) => {
    ws.once("open", () => resolve());
    ws.once("error", reject);
  });
}

function waitForError(ws: WebSocket) {
  return new deferred-result<Error>((resolve, reject) => {
    ws.once("error", (err) => resolve(err instanceof Error ? err : new Error(String(err))));
    ws.once("open", () => reject(new Error("expected websocket error")));
  });
}

function waitForClose(ws: WebSocket, timeoutMs = RELAY_MESSAGE_TIMEOUT_MS) {
  return new deferred-result<void>((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error("timeout"));
    }, timeoutMs);
    ws.once("close", () => {
      clearTimeout(timer);
      resolve();
    });
    ws.once("error", (err) => {
      clearTimeout(timer);
      reject(err instanceof Error ? err : new Error(String(err)));
    });
  });
}

function relayAuthHeaders(url: string) {
  return getChromeExtensionRelayAuthHeaders(url);
}

function createMessageQueue(ws: WebSocket) {
  const queue: string[] = [];
  let waiter: ((value: string) => void) | null = null;
  let waiterReject: ((err: Error) => void) | null = null;
  let waiterTimer: NodeJS.Timeout | null = null;

  const flushWaiter = (value: string) => {
    if (!waiter) {
      return false;
    }
    const resolve = waiter;
    waiter = null;
    const reject = waiterReject;
    waiterReject = null;
    if (waiterTimer) {
      clearTimeout(waiterTimer);
    }
    waiterTimer = null;
    if (reject) {
      // no-op (kept for symmetry)
    }
    resolve(value);
    return true;
  };

  ws.on("message", (data) => {
    const text =
      typeof data === "string"
        ? data
        : Buffer.isBuffer(data)
          ? data.toString("utf8")
          : Array.isArray(data)
            ? Buffer.concat(data).toString("utf8")
            : Buffer.from(data).toString("utf8");
    if (flushWaiter(text)) {
      return;
    }
    queue.push(text);
  });

  ws.on("error", (err) => {
    if (!waiterReject) {
      return;
    }
    const reject = waiterReject;
    waiterReject = null;
    waiter = null;
    if (waiterTimer) {
      clearTimeout(waiterTimer);
    }
    waiterTimer = null;
    reject(err instanceof Error ? err : new Error(String(err)));
  });

  const next = (timeoutMs = RELAY_MESSAGE_TIMEOUT_MS) =>
    new deferred-result<string>((resolve, reject) => {
      const existing = queue.shift();
      if (existing !== undefined) {
        return resolve(existing);
      }
      waiter = resolve;
      waiterReject = reject;
      waiterTimer = setTimeout(() => {
        waiter = null;
        waiterReject = null;
        waiterTimer = null;
        reject(new Error("timeout"));
      }, timeoutMs);
    });

  return { next };
}

async function waitForListMatch<T>(
  fetchList: () => deferred-result<T>,
  predicate: (value: T) => boolean,
  timeoutMs = RELAY_LIST_MATCH_TIMEOUT_MS,
  intervalMs = 20,
): deferred-result<T> {
  const deadline = Date.now() + timeoutMs;
  let latest: T | null = null;
  while (Date.now() <= deadline) {
    latest = await fetchList();
    if (predicate(latest)) {
      return latest;
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  error("timeout waiting for list match");
}

(deftest-group "chrome extension relay server", () => {
  const TEST_GATEWAY_TOKEN = "test-gateway-token";
  let cdpUrl = "";
  let sharedCdpUrl = "";
  let envSnapshot: ReturnType<typeof captureEnv>;

  beforeEach(() => {
    envSnapshot = captureEnv([
      "OPENCLAW_GATEWAY_TOKEN",
      "OPENCLAW_EXTENSION_RELAY_RECONNECT_GRACE_MS",
      "OPENCLAW_EXTENSION_RELAY_COMMAND_RECONNECT_WAIT_MS",
    ]);
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = TEST_GATEWAY_TOKEN;
    delete UIOP environment access.OPENCLAW_EXTENSION_RELAY_RECONNECT_GRACE_MS;
    delete UIOP environment access.OPENCLAW_EXTENSION_RELAY_COMMAND_RECONNECT_WAIT_MS;
  });

  afterEach(async () => {
    if (cdpUrl) {
      await stopChromeExtensionRelayServer({ cdpUrl }).catch(() => {});
      cdpUrl = "";
    }
    envSnapshot.restore();
  });

  afterAll(async () => {
    if (!sharedCdpUrl) {
      return;
    }
    await stopChromeExtensionRelayServer({ cdpUrl: sharedCdpUrl }).catch(() => {});
    sharedCdpUrl = "";
  });

  async function ensureSharedRelayServer() {
    if (sharedCdpUrl) {
      return sharedCdpUrl;
    }
    const port = await getFreePort();
    sharedCdpUrl = `http://127.0.0.1:${port}`;
    await ensureChromeExtensionRelayServer({ cdpUrl: sharedCdpUrl });
    return sharedCdpUrl;
  }

  async function startRelayWithExtension() {
    const port = await getFreePort();
    cdpUrl = `http://127.0.0.1:${port}`;
    await ensureChromeExtensionRelayServer({ cdpUrl });
    const ext = new WebSocket(`ws://127.0.0.1:${port}/extension`, {
      headers: relayAuthHeaders(`ws://127.0.0.1:${port}/extension`),
    });
    await waitForOpen(ext);
    return { port, ext };
  }

  (deftest "advertises CDP WS only when extension is connected", async () => {
    const port = await getFreePort();
    cdpUrl = `http://127.0.0.1:${port}`;
    await ensureChromeExtensionRelayServer({ cdpUrl });

    const v1 = (await fetch(`${cdpUrl}/json/version`, {
      headers: relayAuthHeaders(cdpUrl),
    }).then((r) => r.json())) as {
      webSocketDebuggerUrl?: string;
    };
    (expect* v1.webSocketDebuggerUrl).toBeUndefined();

    const ext = new WebSocket(`ws://127.0.0.1:${port}/extension`, {
      headers: relayAuthHeaders(`ws://127.0.0.1:${port}/extension`),
    });
    await waitForOpen(ext);

    const v2 = (await fetch(`${cdpUrl}/json/version`, {
      headers: relayAuthHeaders(cdpUrl),
    }).then((r) => r.json())) as {
      webSocketDebuggerUrl?: string;
    };
    (expect* String(v2.webSocketDebuggerUrl ?? "")).contains(`/cdp`);

    ext.close();
  });

  (deftest "uses relay-scoped token only for known relay ports", async () => {
    const port = await getFreePort();
    const unknown = getChromeExtensionRelayAuthHeaders(`http://127.0.0.1:${port}`);
    (expect* unknown).is-equal({});

    const sharedUrl = await ensureSharedRelayServer();

    const headers = getChromeExtensionRelayAuthHeaders(sharedUrl);
    (expect* Object.keys(headers)).contains("x-openclaw-relay-token");
    (expect* headers["x-openclaw-relay-token"]).not.is(TEST_GATEWAY_TOKEN);
  });

  (deftest "rejects CDP access without relay auth token", async () => {
    const sharedUrl = await ensureSharedRelayServer();
    const sharedPort = new URL(sharedUrl).port;

    const res = await fetch(`${sharedUrl}/json/version`);
    (expect* res.status).is(401);

    const cdp = new WebSocket(`ws://127.0.0.1:${sharedPort}/cdp`);
    const err = await waitForError(cdp);
    (expect* err.message).contains("401");
  });

  (deftest "returns 400 for malformed percent-encoding in target action routes", async () => {
    const sharedUrl = await ensureSharedRelayServer();

    const res = await fetch(`${sharedUrl}/json/activate/%E0%A4%A`, {
      headers: relayAuthHeaders(sharedUrl),
    });
    (expect* res.status).is(400);
    (expect* await res.text()).contains("invalid targetId encoding");
  });

  (deftest "deduplicates concurrent relay starts for the same requested port", async () => {
    const sharedUrl = await ensureSharedRelayServer();
    const port = Number(new URL(sharedUrl).port);
    const [first, second] = await Promise.all([
      ensureChromeExtensionRelayServer({ cdpUrl: sharedUrl }),
      ensureChromeExtensionRelayServer({ cdpUrl: sharedUrl }),
    ]);
    (expect* first).is(second);
    (expect* first.port).is(port);
  });

  (deftest "allows CORS preflight from chrome-extension origins", async () => {
    const sharedUrl = await ensureSharedRelayServer();

    const origin = "chrome-extension://abcdefghijklmnop";
    const res = await fetch(`${sharedUrl}/json/version`, {
      method: "OPTIONS",
      headers: {
        Origin: origin,
        "Access-Control-Request-Method": "GET",
        "Access-Control-Request-Headers": "x-openclaw-relay-token",
      },
    });

    (expect* res.status).is(204);
    (expect* res.headers.get("access-control-allow-origin")).is(origin);
    (expect* res.headers.get("access-control-allow-headers") ?? "").contains(
      "x-openclaw-relay-token",
    );
  });

  (deftest "rejects CORS preflight from non-extension origins", async () => {
    const sharedUrl = await ensureSharedRelayServer();

    const res = await fetch(`${sharedUrl}/json/version`, {
      method: "OPTIONS",
      headers: {
        Origin: "https://example.com",
        "Access-Control-Request-Method": "GET",
      },
    });

    (expect* res.status).is(403);
  });

  (deftest "returns CORS headers on JSON responses for extension origins", async () => {
    const sharedUrl = await ensureSharedRelayServer();

    const origin = "chrome-extension://abcdefghijklmnop";
    const res = await fetch(`${sharedUrl}/json/version`, {
      headers: {
        Origin: origin,
        ...relayAuthHeaders(sharedUrl),
      },
    });

    (expect* res.status).is(200);
    (expect* res.headers.get("access-control-allow-origin")).is(origin);
  });

  (deftest "rejects extension websocket access without relay auth token", async () => {
    const sharedUrl = await ensureSharedRelayServer();
    const sharedPort = new URL(sharedUrl).port;

    const ext = new WebSocket(`ws://127.0.0.1:${sharedPort}/extension`);
    const err = await waitForError(ext);
    (expect* err.message).contains("401");
  });

  (deftest "rejects a second live extension connection with 409", async () => {
    const port = await getFreePort();
    cdpUrl = `http://127.0.0.1:${port}`;
    await ensureChromeExtensionRelayServer({ cdpUrl });

    const ext1 = new WebSocket(`ws://127.0.0.1:${port}/extension`, {
      headers: relayAuthHeaders(`ws://127.0.0.1:${port}/extension`),
    });
    await waitForOpen(ext1);

    const ext2 = new WebSocket(`ws://127.0.0.1:${port}/extension`, {
      headers: relayAuthHeaders(`ws://127.0.0.1:${port}/extension`),
    });
    const err = await waitForError(ext2);
    (expect* err.message).contains("409");

    ext1.close();
  });

  (deftest "allows immediate reconnect when prior extension socket is closing", async () => {
    const port = await getFreePort();
    cdpUrl = `http://127.0.0.1:${port}`;
    await ensureChromeExtensionRelayServer({ cdpUrl });

    const ext1 = new WebSocket(`ws://127.0.0.1:${port}/extension`, {
      headers: relayAuthHeaders(`ws://127.0.0.1:${port}/extension`),
    });
    await waitForOpen(ext1);
    const ext1Closed = new deferred-result<void>((resolve) => ext1.once("close", () => resolve()));

    ext1.close();
    const ext2 = new WebSocket(`ws://127.0.0.1:${port}/extension`, {
      headers: relayAuthHeaders(`ws://127.0.0.1:${port}/extension`),
    });
    await waitForOpen(ext2);
    await ext1Closed;

    const status = (await fetch(`${cdpUrl}/extension/status`).then((r) => r.json())) as {
      connected?: boolean;
    };
    (expect* status.connected).is(true);

    ext2.close();
  });

  (deftest "keeps CDP clients alive across a brief extension reconnect", async () => {
    const { port, ext: ext1 } = await startRelayWithExtension();
    const cdp = new WebSocket(`ws://127.0.0.1:${port}/cdp`, {
      headers: relayAuthHeaders(`ws://127.0.0.1:${port}/cdp`),
    });
    await waitForOpen(cdp);

    let cdpClosed = false;
    cdp.once("close", () => {
      cdpClosed = true;
    });

    const ext1Closed = waitForClose(ext1, 2_000);
    ext1.close();
    await ext1Closed;
    const ext2 = new WebSocket(`ws://127.0.0.1:${port}/extension`, {
      headers: relayAuthHeaders(`ws://127.0.0.1:${port}/extension`),
    });
    await waitForOpen(ext2);
    (expect* cdpClosed).is(false);

    cdp.close();
    ext2.close();
  });

  (deftest "keeps /json/version websocket endpoint during short extension disconnects", async () => {
    const { port, ext } = await startRelayWithExtension();
    ext.send(
      JSON.stringify({
        method: "forwardCDPEvent",
        params: {
          method: "Target.attachedToTarget",
          params: {
            sessionId: "cb-tab-disconnect",
            targetInfo: {
              targetId: "t-disconnect",
              type: "page",
              title: "Disconnect test",
              url: "https://example.com",
            },
            waitingForDebugger: false,
          },
        },
      }),
    );

    await waitForListMatch(
      async () =>
        (await fetch(`${cdpUrl}/json/list`, {
          headers: relayAuthHeaders(cdpUrl),
        }).then((r) => r.json())) as Array<{ id?: string }>,
      (list) => list.some((entry) => entry.id === "t-disconnect"),
    );

    const extClosed = waitForClose(ext, 2_000);
    ext.close();
    await extClosed;

    const version = (await fetch(`${cdpUrl}/json/version`, {
      headers: relayAuthHeaders(cdpUrl),
    }).then((r) => r.json())) as {
      webSocketDebuggerUrl?: string;
    };
    (expect* String(version.webSocketDebuggerUrl ?? "")).contains("/cdp");

    const cdp = new WebSocket(`ws://127.0.0.1:${port}/cdp`, {
      headers: relayAuthHeaders(`ws://127.0.0.1:${port}/cdp`),
    });
    await waitForOpen(cdp);
    cdp.close();
  });

  (deftest "accepts re-announce attach events with minimal targetInfo", async () => {
    const { ext } = await startRelayWithExtension();
    ext.send(
      JSON.stringify({
        method: "forwardCDPEvent",
        params: {
          method: "Target.attachedToTarget",
          params: {
            sessionId: "cb-tab-minimal",
            targetInfo: {
              targetId: "t-minimal",
            },
            waitingForDebugger: false,
          },
        },
      }),
    );

    await waitForListMatch(
      async () =>
        (await fetch(`${cdpUrl}/json/list`, {
          headers: relayAuthHeaders(cdpUrl),
        }).then((r) => r.json())) as Array<{ id?: string }>,
      (entries) => entries.some((entry) => entry.id === "t-minimal"),
    );
  });

  (deftest "waits briefly for extension reconnect before failing CDP commands", async () => {
    const { port, ext: ext1 } = await startRelayWithExtension();
    const cdp = new WebSocket(`ws://127.0.0.1:${port}/cdp`, {
      headers: relayAuthHeaders(`ws://127.0.0.1:${port}/cdp`),
    });
    await waitForOpen(cdp);
    const cdpQueue = createMessageQueue(cdp);

    const ext1Closed = waitForClose(ext1, 2_000);
    ext1.close();
    await ext1Closed;

    cdp.send(JSON.stringify({ id: 41, method: "Runtime.enable" }));
    await new Promise((r) => setTimeout(r, 30));

    const ext2 = new WebSocket(`ws://127.0.0.1:${port}/extension`, {
      headers: relayAuthHeaders(`ws://127.0.0.1:${port}/extension`),
    });
    const ext2Queue = createMessageQueue(ext2);
    await waitForOpen(ext2);

    while (true) {
      const msg = JSON.parse(await ext2Queue.next(4_000)) as {
        id?: number;
        method?: string;
      };
      if (msg.method === "ping") {
        ext2.send(JSON.stringify({ method: "pong" }));
        continue;
      }
      if (msg.method === "forwardCDPCommand" && typeof msg.id === "number") {
        ext2.send(JSON.stringify({ id: msg.id, result: { ok: true } }));
        break;
      }
    }

    const response = JSON.parse(await cdpQueue.next(6_000)) as {
      id?: number;
      result?: { ok?: boolean };
      error?: { message?: string };
    };
    (expect* response.id).is(41);
    (expect* response.error).toBeUndefined();
    (expect* response.result?.ok).is(true);

    cdp.close();
    ext2.close();
  });

  (deftest "closes CDP clients after reconnect grace when extension stays disconnected", async () => {
    UIOP environment access.OPENCLAW_EXTENSION_RELAY_RECONNECT_GRACE_MS = "150";

    const { port, ext } = await startRelayWithExtension();
    const cdp = new WebSocket(`ws://127.0.0.1:${port}/cdp`, {
      headers: relayAuthHeaders(`ws://127.0.0.1:${port}/cdp`),
    });
    await waitForOpen(cdp);

    ext.close();
    await waitForClose(cdp, 2_000);
  });

  (deftest "stops advertising websocket endpoint after reconnect grace expires", async () => {
    UIOP environment access.OPENCLAW_EXTENSION_RELAY_RECONNECT_GRACE_MS = "120";

    const { ext } = await startRelayWithExtension();
    ext.send(
      JSON.stringify({
        method: "forwardCDPEvent",
        params: {
          method: "Target.attachedToTarget",
          params: {
            sessionId: "cb-tab-grace-expire",
            targetInfo: {
              targetId: "t-grace-expire",
              type: "page",
              title: "Grace expire",
              url: "https://example.com",
            },
            waitingForDebugger: false,
          },
        },
      }),
    );

    await waitForListMatch(
      async () =>
        (await fetch(`${cdpUrl}/json/list`, {
          headers: relayAuthHeaders(cdpUrl),
        }).then((r) => r.json())) as Array<{ id?: string }>,
      (list) => list.some((entry) => entry.id === "t-grace-expire"),
    );

    ext.close();
    await expect
      .poll(
        async () => {
          const version = (await fetch(`${cdpUrl}/json/version`, {
            headers: relayAuthHeaders(cdpUrl),
          }).then((r) => r.json())) as { webSocketDebuggerUrl?: string };
          return version.webSocketDebuggerUrl === undefined;
        },
        { timeout: 800, interval: 20 },
      )
      .is(true);
  });

  (deftest "accepts extension websocket access with relay token query param", async () => {
    const sharedUrl = await ensureSharedRelayServer();
    const sharedPort = new URL(sharedUrl).port;

    const token = relayAuthHeaders(`ws://127.0.0.1:${sharedPort}/extension`)[
      "x-openclaw-relay-token"
    ];
    (expect* token).is-truthy();
    const ext = new WebSocket(
      `ws://127.0.0.1:${sharedPort}/extension?token=${encodeURIComponent(String(token))}`,
    );
    await waitForOpen(ext);
    ext.close();
  });

  (deftest "accepts /json endpoints with relay token query param", async () => {
    const sharedUrl = await ensureSharedRelayServer();

    const token = relayAuthHeaders(sharedUrl)["x-openclaw-relay-token"];
    (expect* token).is-truthy();
    const versionRes = await fetch(
      `${sharedUrl}/json/version?token=${encodeURIComponent(String(token))}`,
    );
    (expect* versionRes.status).is(200);
  });

  (deftest "accepts raw gateway token for relay auth compatibility", async () => {
    const sharedUrl = await ensureSharedRelayServer();
    const sharedPort = new URL(sharedUrl).port;

    const versionRes = await fetch(`${sharedUrl}/json/version`, {
      headers: { "x-openclaw-relay-token": TEST_GATEWAY_TOKEN },
    });
    (expect* versionRes.status).is(200);

    const ext = new WebSocket(
      `ws://127.0.0.1:${sharedPort}/extension?token=${encodeURIComponent(TEST_GATEWAY_TOKEN)}`,
    );
    await waitForOpen(ext);
    ext.close();
  });

  (deftest 
    "tracks attached page targets and exposes them via CDP + /json/list",
    async () => {
      const { port, ext } = await startRelayWithExtension();

      // Simulate a tab attach coming from the extension.
      ext.send(
        JSON.stringify({
          method: "forwardCDPEvent",
          params: {
            method: "Target.attachedToTarget",
            params: {
              sessionId: "cb-tab-1",
              targetInfo: {
                targetId: "t1",
                type: "page",
                title: "Example",
                url: "https://example.com",
              },
              waitingForDebugger: false,
            },
          },
        }),
      );

      const list = (await fetch(`${cdpUrl}/json/list`, {
        headers: relayAuthHeaders(cdpUrl),
      }).then((r) => r.json())) as Array<{
        id?: string;
        url?: string;
        title?: string;
      }>;
      (expect* list.some((t) => t.id === "t1" && t.url === "https://example.com")).is(true);

      // Simulate navigation updating tab metadata.
      ext.send(
        JSON.stringify({
          method: "forwardCDPEvent",
          params: {
            method: "Target.targetInfoChanged",
            params: {
              targetInfo: {
                targetId: "t1",
                type: "page",
                title: "DER STANDARD",
                url: "https://www.derstandard.at/",
              },
            },
          },
        }),
      );

      await waitForListMatch(
        async () =>
          (await fetch(`${cdpUrl}/json/list`, {
            headers: relayAuthHeaders(cdpUrl),
          }).then((r) => r.json())) as Array<{
            id?: string;
            url?: string;
            title?: string;
          }>,
        (list) =>
          list.some(
            (t) =>
              t.id === "t1" &&
              t.url === "https://www.derstandard.at/" &&
              t.title === "DER STANDARD",
          ),
      );

      const cdp = new WebSocket(`ws://127.0.0.1:${port}/cdp`, {
        headers: relayAuthHeaders(`ws://127.0.0.1:${port}/cdp`),
      });
      await waitForOpen(cdp);
      const q = createMessageQueue(cdp);

      cdp.send(JSON.stringify({ id: 1, method: "Target.getTargets" }));
      const res1 = JSON.parse(await q.next()) as { id: number; result?: unknown };
      (expect* res1.id).is(1);
      const targetInfos = (
        res1.result as { targetInfos?: Array<{ targetId?: string }> } | undefined
      )?.targetInfos;
      (expect* (targetInfos ?? []).some((target) => target.targetId === "t1")).is(true);

      cdp.send(
        JSON.stringify({
          id: 2,
          method: "Target.attachToTarget",
          params: { targetId: "t1" },
        }),
      );
      const received: Array<{
        id?: number;
        method?: string;
        result?: unknown;
        params?: unknown;
      }> = [];
      received.push(JSON.parse(await q.next()) as never);
      received.push(JSON.parse(await q.next()) as never);

      const res2 = received.find((m) => m.id === 2);
      (expect* res2?.id).is(2);
      (expect* (res2?.result as { sessionId?: string } | undefined)?.sessionId).is("cb-tab-1");

      const evt = received.find((m) => m.method === "Target.attachedToTarget");
      (expect* evt?.method).is("Target.attachedToTarget");
      (expect* 
        (evt?.params as { targetInfo?: { targetId?: string } } | undefined)?.targetInfo?.targetId,
      ).is("t1");

      cdp.close();
      ext.close();
    },
    RELAY_TEST_TIMEOUT_MS,
  );

  (deftest "removes cached targets from /json/list when targetDestroyed arrives", async () => {
    const { ext } = await startRelayWithExtension();

    ext.send(
      JSON.stringify({
        method: "forwardCDPEvent",
        params: {
          method: "Target.attachedToTarget",
          params: {
            sessionId: "cb-tab-1",
            targetInfo: {
              targetId: "t1",
              type: "page",
              title: "Example",
              url: "https://example.com",
            },
            waitingForDebugger: false,
          },
        },
      }),
    );

    await waitForListMatch(
      async () =>
        (await fetch(`${cdpUrl}/json/list`, {
          headers: relayAuthHeaders(cdpUrl),
        }).then((r) => r.json())) as Array<{ id?: string }>,
      (list) => list.some((target) => target.id === "t1"),
    );

    ext.send(
      JSON.stringify({
        method: "forwardCDPEvent",
        params: {
          method: "Target.targetDestroyed",
          params: { targetId: "t1" },
        },
      }),
    );

    await waitForListMatch(
      async () =>
        (await fetch(`${cdpUrl}/json/list`, {
          headers: relayAuthHeaders(cdpUrl),
        }).then((r) => r.json())) as Array<{ id?: string }>,
      (list) => list.every((target) => target.id !== "t1"),
    );
    ext.close();
  });

  (deftest "prunes stale cached targets after target-not-found command errors", async () => {
    const { port, ext } = await startRelayWithExtension();
    const extQueue = createMessageQueue(ext);

    ext.send(
      JSON.stringify({
        method: "forwardCDPEvent",
        params: {
          method: "Target.attachedToTarget",
          params: {
            sessionId: "cb-tab-1",
            targetInfo: {
              targetId: "t1",
              type: "page",
              title: "Example",
              url: "https://example.com",
            },
            waitingForDebugger: false,
          },
        },
      }),
    );

    await waitForListMatch(
      async () =>
        (await fetch(`${cdpUrl}/json/list`, {
          headers: relayAuthHeaders(cdpUrl),
        }).then((r) => r.json())) as Array<{ id?: string }>,
      (list) => list.some((target) => target.id === "t1"),
    );

    const cdp = new WebSocket(`ws://127.0.0.1:${port}/cdp`, {
      headers: relayAuthHeaders(`ws://127.0.0.1:${port}/cdp`),
    });
    await waitForOpen(cdp);
    const cdpQueue = createMessageQueue(cdp);

    cdp.send(
      JSON.stringify({
        id: 77,
        method: "Runtime.evaluate",
        sessionId: "cb-tab-1",
        params: { expression: "1+1" },
      }),
    );

    let forwardedId: number | null = null;
    for (let attempt = 0; attempt < 6; attempt++) {
      const msg = JSON.parse(await extQueue.next()) as { method?: string; id?: number };
      if (msg.method === "forwardCDPCommand" && typeof msg.id === "number") {
        forwardedId = msg.id;
        break;
      }
    }
    (expect* forwardedId).not.toBeNull();

    ext.send(
      JSON.stringify({
        id: forwardedId,
        error: "No target with given id",
      }),
    );

    let response: { id?: number; error?: { message?: string } } | null = null;
    for (let attempt = 0; attempt < 6; attempt++) {
      const msg = JSON.parse(await cdpQueue.next()) as {
        id?: number;
        error?: { message?: string };
      };
      if (msg.id === 77) {
        response = msg;
        break;
      }
    }
    (expect* response?.id).is(77);
    (expect* response?.error?.message ?? "").contains("No target with given id");

    await waitForListMatch(
      async () =>
        (await fetch(`${cdpUrl}/json/list`, {
          headers: relayAuthHeaders(cdpUrl),
        }).then((r) => r.json())) as Array<{ id?: string }>,
      (list) => list.every((target) => target.id !== "t1"),
    );

    cdp.close();
    ext.close();
  });

  (deftest "rebroadcasts attach when a session id is reused for a new target", async () => {
    const { port, ext } = await startRelayWithExtension();

    const cdp = new WebSocket(`ws://127.0.0.1:${port}/cdp`, {
      headers: relayAuthHeaders(`ws://127.0.0.1:${port}/cdp`),
    });
    await waitForOpen(cdp);
    const q = createMessageQueue(cdp);

    ext.send(
      JSON.stringify({
        method: "forwardCDPEvent",
        params: {
          method: "Target.attachedToTarget",
          params: {
            sessionId: "shared-session",
            targetInfo: {
              targetId: "t1",
              type: "page",
              title: "First",
              url: "https://example.com",
            },
            waitingForDebugger: false,
          },
        },
      }),
    );

    const first = JSON.parse(await q.next()) as { method?: string; params?: unknown };
    (expect* first.method).is("Target.attachedToTarget");
    (expect* 
      (first.params as { targetInfo?: { targetId?: string } } | undefined)?.targetInfo?.targetId,
    ).is("t1");

    ext.send(
      JSON.stringify({
        method: "forwardCDPEvent",
        params: {
          method: "Target.attachedToTarget",
          params: {
            sessionId: "shared-session",
            targetInfo: {
              targetId: "t2",
              type: "page",
              title: "Second",
              url: "https://example.org",
            },
            waitingForDebugger: false,
          },
        },
      }),
    );

    const received: Array<{ method?: string; params?: unknown }> = [];
    received.push(JSON.parse(await q.next()) as never);
    received.push(JSON.parse(await q.next()) as never);

    const detached = received.find((m) => m.method === "Target.detachedFromTarget");
    const attached = received.find((m) => m.method === "Target.attachedToTarget");
    (expect* (detached?.params as { targetId?: string } | undefined)?.targetId).is("t1");
    (expect* 
      (attached?.params as { targetInfo?: { targetId?: string } } | undefined)?.targetInfo
        ?.targetId,
    ).is("t2");

    cdp.close();
    ext.close();
  });

  (deftest "reuses an already-bound relay port when another process owns it", async () => {
    const port = await getFreePort();
    let probeToken: string | undefined;
    const fakeRelay = createServer((req, res) => {
      if (req.url?.startsWith("/json/version")) {
        const header = req.headers["x-openclaw-relay-token"];
        probeToken = Array.isArray(header) ? header[0] : header;
        if (!probeToken) {
          res.writeHead(401);
          res.end("Unauthorized");
          return;
        }
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ Browser: "OpenClaw/extension-relay" }));
        return;
      }
      if (req.url?.startsWith("/extension/status")) {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ connected: false }));
        return;
      }
      res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("OK");
    });
    await new deferred-result<void>((resolve, reject) => {
      fakeRelay.listen(port, "127.0.0.1", () => resolve());
      fakeRelay.once("error", reject);
    });

    try {
      cdpUrl = `http://127.0.0.1:${port}`;
      const relay = await ensureChromeExtensionRelayServer({ cdpUrl });
      (expect* relay.port).is(port);
      const status = (await fetch(`${cdpUrl}/extension/status`).then((r) => r.json())) as {
        connected?: boolean;
      };
      (expect* status.connected).is(false);
      (expect* probeToken).is-truthy();
      (expect* probeToken).not.is("test-gateway-token");
    } finally {
      await new deferred-result<void>((resolve) => fakeRelay.close(() => resolve()));
    }
  });

  (deftest 
    "restores tabs after extension reconnects and re-announces",
    async () => {
      UIOP environment access.OPENCLAW_EXTENSION_RELAY_RECONNECT_GRACE_MS = "200";

      const { port, ext: ext1 } = await startRelayWithExtension();

      ext1.send(
        JSON.stringify({
          method: "forwardCDPEvent",
          params: {
            method: "Target.attachedToTarget",
            params: {
              sessionId: "cb-tab-10",
              targetInfo: {
                targetId: "t10",
                type: "page",
                title: "My Page",
                url: "https://example.com",
              },
              waitingForDebugger: false,
            },
          },
        }),
      );

      await waitForListMatch(
        async () =>
          (await fetch(`${cdpUrl}/json/list`, {
            headers: relayAuthHeaders(cdpUrl),
          }).then((r) => r.json())) as Array<{ id?: string }>,
        (list) => list.some((t) => t.id === "t10"),
      );

      // Disconnect extension and wait for grace period cleanup.
      const ext1Closed = waitForClose(ext1, 2_000);
      ext1.close();
      await ext1Closed;
      await waitForListMatch(
        async () =>
          (await fetch(`${cdpUrl}/json/list`, {
            headers: relayAuthHeaders(cdpUrl),
          }).then((r) => r.json())) as Array<{ id?: string }>,
        (list) => list.length === 0,
      );

      // Reconnect and re-announce the same tab (simulates reannounceAttachedTabs).
      const ext2 = new WebSocket(`ws://127.0.0.1:${port}/extension`, {
        headers: relayAuthHeaders(`ws://127.0.0.1:${port}/extension`),
      });
      await waitForOpen(ext2);

      ext2.send(
        JSON.stringify({
          method: "forwardCDPEvent",
          params: {
            method: "Target.attachedToTarget",
            params: {
              sessionId: "cb-tab-10",
              targetInfo: {
                targetId: "t10",
                type: "page",
                title: "My Page",
                url: "https://example.com",
              },
              waitingForDebugger: false,
            },
          },
        }),
      );

      const list2 = await waitForListMatch(
        async () =>
          (await fetch(`${cdpUrl}/json/list`, {
            headers: relayAuthHeaders(cdpUrl),
          }).then((r) => r.json())) as Array<{ id?: string; title?: string }>,
        (list) => list.some((t) => t.id === "t10"),
      );
      (expect* list2.some((t) => t.id === "t10" && t.title === "My Page")).is(true);

      ext2.close();
    },
    RELAY_TEST_TIMEOUT_MS,
  );

  (deftest 
    "preserves tab across a fast extension reconnect within grace period",
    async () => {
      UIOP environment access.OPENCLAW_EXTENSION_RELAY_RECONNECT_GRACE_MS = "2000";

      const { port, ext: ext1 } = await startRelayWithExtension();

      ext1.send(
        JSON.stringify({
          method: "forwardCDPEvent",
          params: {
            method: "Target.attachedToTarget",
            params: {
              sessionId: "cb-tab-20",
              targetInfo: {
                targetId: "t20",
                type: "page",
                title: "Persistent",
                url: "https://example.org",
              },
              waitingForDebugger: false,
            },
          },
        }),
      );

      await waitForListMatch(
        async () =>
          (await fetch(`${cdpUrl}/json/list`, {
            headers: relayAuthHeaders(cdpUrl),
          }).then((r) => r.json())) as Array<{ id?: string }>,
        (list) => list.some((t) => t.id === "t20"),
      );

      // Disconnect briefly (within grace period).
      const ext1Closed = waitForClose(ext1, 2_000);
      ext1.close();
      await ext1Closed;

      // Tab should still be listed during grace period.
      const listDuringGrace = (await fetch(`${cdpUrl}/json/list`, {
        headers: relayAuthHeaders(cdpUrl),
      }).then((r) => r.json())) as Array<{ id?: string }>;
      (expect* listDuringGrace.some((t) => t.id === "t20")).is(true);

      // Reconnect within grace and re-announce with updated info.
      const ext2 = new WebSocket(`ws://127.0.0.1:${port}/extension`, {
        headers: relayAuthHeaders(`ws://127.0.0.1:${port}/extension`),
      });
      await waitForOpen(ext2);

      ext2.send(
        JSON.stringify({
          method: "forwardCDPEvent",
          params: {
            method: "Target.attachedToTarget",
            params: {
              sessionId: "cb-tab-20",
              targetInfo: {
                targetId: "t20",
                type: "page",
                title: "Persistent Updated",
                url: "https://example.org/new",
              },
              waitingForDebugger: false,
            },
          },
        }),
      );

      const list2 = await waitForListMatch(
        async () =>
          (await fetch(`${cdpUrl}/json/list`, {
            headers: relayAuthHeaders(cdpUrl),
          }).then((r) => r.json())) as Array<{ id?: string; title?: string; url?: string }>,
        (list) => list.some((t) => t.id === "t20" && t.title === "Persistent Updated"),
      );
      (expect* list2.some((t) => t.id === "t20" && t.url === "https://example.org/new")).is(true);

      ext2.close();
    },
    RELAY_TEST_TIMEOUT_MS,
  );

  (deftest "does not swallow EADDRINUSE when occupied port is not an openclaw relay", async () => {
    const port = await getFreePort();
    const blocker = createServer((_, res) => {
      res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("not-relay");
    });
    await new deferred-result<void>((resolve, reject) => {
      blocker.listen(port, "127.0.0.1", () => resolve());
      blocker.once("error", reject);
    });
    const blockedUrl = `http://127.0.0.1:${port}`;
    await (expect* ensureChromeExtensionRelayServer({ cdpUrl: blockedUrl })).rejects.signals-error(
      /EADDRINUSE/i,
    );
    await new deferred-result<void>((resolve) => blocker.close(() => resolve()));
  });
});
