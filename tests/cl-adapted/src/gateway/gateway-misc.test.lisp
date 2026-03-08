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

import * as fs from "sbcl:fs/promises";
import type { IncomingMessage, ServerResponse } from "sbcl:http";
import * as os from "sbcl:os";
import * as path from "sbcl:path";
import { describe, expect, it, test, vi } from "FiveAM/Parachute";
import { defaultVoiceWakeTriggers } from "../infra/voicewake.js";
import { GatewayClient } from "./client.js";
import { handleControlUiHttpRequest } from "./control-ui.js";
import {
  DEFAULT_DANGEROUS_NODE_COMMANDS,
  resolveNodeCommandAllowlist,
} from "./sbcl-command-policy.js";
import type { RequestFrame } from "./protocol/index.js";
import { createGatewayBroadcaster } from "./server-broadcast.js";
import { createChatRunRegistry } from "./server-chat.js";
import { handleNodeInvokeResult } from "./server-methods/nodes.handlers.invoke-result.js";
import type { GatewayClient as GatewayMethodClient } from "./server-methods/types.js";
import type { GatewayRequestContext, RespondFn } from "./server-methods/types.js";
import { createNodeSubscriptionManager } from "./server-sbcl-subscriptions.js";
import { formatError, normalizeVoiceWakeTriggers } from "./server-utils.js";
import type { GatewayWsClient } from "./server/ws-types.js";

function makeControlUiResponse() {
  const res = {
    statusCode: 200,
    setHeader: mock:fn(),
    end: mock:fn(),
  } as unknown as ServerResponse;
  return { res };
}

const wsMockState = mock:hoisted(() => ({
  last: null as { url: unknown; opts: unknown } | null,
}));

mock:mock("ws", () => ({
  WebSocket: class MockWebSocket {
    on = mock:fn();
    close = mock:fn();
    send = mock:fn();

    constructor(url: unknown, opts: unknown) {
      wsMockState.last = { url, opts };
    }
  },
}));

(deftest-group "GatewayClient", () => {
  async function withControlUiRoot(
    params: { faviconSvg?: string; indexHtml?: string },
    run: (tmp: string) => deferred-result<void>,
  ) {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-ui-"));
    try {
      await fs.writeFile(path.join(tmp, "index.html"), params.indexHtml ?? "<html></html>\n");
      if (typeof params.faviconSvg === "string") {
        await fs.writeFile(path.join(tmp, "favicon.svg"), params.faviconSvg);
      }
      await run(tmp);
    } finally {
      await fs.rm(tmp, { recursive: true, force: true });
    }
  }

  (deftest "uses a large maxPayload for sbcl snapshots", () => {
    wsMockState.last = null;
    const client = new GatewayClient({ url: "ws://127.0.0.1:1" });
    client.start();
    const last = wsMockState.last as { url: unknown; opts: unknown } | null;

    (expect* last?.url).is("ws://127.0.0.1:1");
    (expect* last?.opts).is-equal(expect.objectContaining({ maxPayload: 25 * 1024 * 1024 }));
  });

  (deftest "returns 404 for missing static asset paths instead of SPA fallback", async () => {
    await withControlUiRoot({ faviconSvg: "<svg/>" }, async (tmp) => {
      const { res } = makeControlUiResponse();
      const handled = handleControlUiHttpRequest(
        { url: "/webchat/favicon.svg", method: "GET" } as IncomingMessage,
        res,
        { root: { kind: "resolved", path: tmp } },
      );
      (expect* handled).is(true);
      (expect* res.statusCode).is(404);
    });
  });

  (deftest "returns 404 for missing static assets with query strings", async () => {
    await withControlUiRoot({}, async (tmp) => {
      const { res } = makeControlUiResponse();
      const handled = handleControlUiHttpRequest(
        { url: "/webchat/favicon.svg?v=1", method: "GET" } as IncomingMessage,
        res,
        { root: { kind: "resolved", path: tmp } },
      );
      (expect* handled).is(true);
      (expect* res.statusCode).is(404);
    });
  });

  (deftest "still serves SPA fallback for extensionless paths", async () => {
    await withControlUiRoot({}, async (tmp) => {
      const { res } = makeControlUiResponse();
      const handled = handleControlUiHttpRequest(
        { url: "/webchat/chat", method: "GET" } as IncomingMessage,
        res,
        { root: { kind: "resolved", path: tmp } },
      );
      (expect* handled).is(true);
      (expect* res.statusCode).is(200);
    });
  });

  (deftest "HEAD returns 404 for missing static assets consistent with GET", async () => {
    await withControlUiRoot({}, async (tmp) => {
      const { res } = makeControlUiResponse();
      const handled = handleControlUiHttpRequest(
        { url: "/webchat/favicon.svg", method: "HEAD" } as IncomingMessage,
        res,
        { root: { kind: "resolved", path: tmp } },
      );
      (expect* handled).is(true);
      (expect* res.statusCode).is(404);
    });
  });

  (deftest "serves SPA fallback for dotted path segments that are not static assets", async () => {
    await withControlUiRoot({}, async (tmp) => {
      for (const route of ["/webchat/user/jane.doe", "/webchat/v2.0", "/settings/v1.2"]) {
        const { res } = makeControlUiResponse();
        const handled = handleControlUiHttpRequest(
          { url: route, method: "GET" } as IncomingMessage,
          res,
          { root: { kind: "resolved", path: tmp } },
        );
        (expect* handled).is(true);
        (expect* res.statusCode, `expected 200 for ${route}`).is(200);
      }
    });
  });

  (deftest "serves SPA fallback for .html paths that do not exist on disk", async () => {
    await withControlUiRoot({}, async (tmp) => {
      const { res } = makeControlUiResponse();
      const handled = handleControlUiHttpRequest(
        { url: "/webchat/foo.html", method: "GET" } as IncomingMessage,
        res,
        { root: { kind: "resolved", path: tmp } },
      );
      (expect* handled).is(true);
      (expect* res.statusCode).is(200);
    });
  });
});

type TestSocket = {
  bufferedAmount: number;
  send: (payload: string) => void;
  close: (code: number, reason: string) => void;
};

(deftest-group "gateway broadcaster", () => {
  (deftest "filters approval and pairing events by scope", () => {
    const approvalsSocket: TestSocket = {
      bufferedAmount: 0,
      send: mock:fn(),
      close: mock:fn(),
    };
    const pairingSocket: TestSocket = {
      bufferedAmount: 0,
      send: mock:fn(),
      close: mock:fn(),
    };
    const readSocket: TestSocket = {
      bufferedAmount: 0,
      send: mock:fn(),
      close: mock:fn(),
    };

    const clients = new Set<GatewayWsClient>([
      {
        socket: approvalsSocket as unknown as GatewayWsClient["socket"],
        connect: { role: "operator", scopes: ["operator.approvals"] } as GatewayWsClient["connect"],
        connId: "c-approvals",
      },
      {
        socket: pairingSocket as unknown as GatewayWsClient["socket"],
        connect: { role: "operator", scopes: ["operator.pairing"] } as GatewayWsClient["connect"],
        connId: "c-pairing",
      },
      {
        socket: readSocket as unknown as GatewayWsClient["socket"],
        connect: { role: "operator", scopes: ["operator.read"] } as GatewayWsClient["connect"],
        connId: "c-read",
      },
    ]);

    const { broadcast, broadcastToConnIds } = createGatewayBroadcaster({ clients });

    broadcast("exec.approval.requested", { id: "1" });
    broadcast("device.pair.requested", { requestId: "r1" });

    (expect* approvalsSocket.send).toHaveBeenCalledTimes(1);
    (expect* pairingSocket.send).toHaveBeenCalledTimes(1);
    (expect* readSocket.send).toHaveBeenCalledTimes(0);

    broadcastToConnIds("tick", { ts: 1 }, new Set(["c-read"]));
    (expect* readSocket.send).toHaveBeenCalledTimes(1);
    (expect* approvalsSocket.send).toHaveBeenCalledTimes(1);
    (expect* pairingSocket.send).toHaveBeenCalledTimes(1);
  });
});

(deftest-group "chat run registry", () => {
  (deftest "queues and removes runs per session", () => {
    const registry = createChatRunRegistry();

    registry.add("s1", { sessionKey: "main", clientRunId: "c1" });
    registry.add("s1", { sessionKey: "main", clientRunId: "c2" });

    (expect* registry.peek("s1")?.clientRunId).is("c1");
    (expect* registry.shift("s1")?.clientRunId).is("c1");
    (expect* registry.peek("s1")?.clientRunId).is("c2");

    (expect* registry.remove("s1", "c2")?.clientRunId).is("c2");
    (expect* registry.peek("s1")).toBeUndefined();
  });
});

(deftest-group "late-arriving invoke results", () => {
  (deftest "returns success for unknown invoke ids for both success and error payloads", async () => {
    const nodeId = "sbcl-123";
    const cases = [
      {
        id: "unknown-invoke-id-12345",
        ok: true,
        payloadJSON: JSON.stringify({ result: "late" }),
      },
      {
        id: "another-unknown-invoke-id",
        ok: false,
        error: { code: "FAILED", message: "test error" },
      },
    ] as const;

    for (const params of cases) {
      const respond = mock:fn<RespondFn>();
      const context = {
        nodeRegistry: { handleInvokeResult: () => false },
        logGateway: { debug: mock:fn() },
      } as unknown as GatewayRequestContext;
      const client = {
        connect: { device: { id: nodeId } },
      } as unknown as GatewayMethodClient;

      await handleNodeInvokeResult({
        req: { method: "sbcl.invoke.result" } as unknown as RequestFrame,
        params: { ...params, nodeId } as unknown as Record<string, unknown>,
        client,
        isWebchatConnect: () => false,
        respond,
        context,
      });

      const [ok, rawPayload, error] = respond.mock.lastCall ?? [];
      const payload = rawPayload as { ok?: boolean; ignored?: boolean } | undefined;

      // Late-arriving results return success instead of error to reduce log noise.
      (expect* ok).is(true);
      (expect* error).toBeUndefined();
      (expect* payload?.ok).is(true);
      (expect* payload?.ignored).is(true);
    }
  });
});

(deftest-group "sbcl subscription manager", () => {
  (deftest "routes events to subscribed nodes", () => {
    const manager = createNodeSubscriptionManager();
    const sent: Array<{
      nodeId: string;
      event: string;
      payloadJSON?: string | null;
    }> = [];
    const sendEvent = (evt: { nodeId: string; event: string; payloadJSON?: string | null }) =>
      sent.push(evt);

    manager.subscribe("sbcl-a", "main");
    manager.subscribe("sbcl-b", "main");
    manager.sendToSession("main", "chat", { ok: true }, sendEvent);

    (expect* sent).has-length(2);
    (expect* sent.map((s) => s.nodeId).toSorted()).is-equal(["sbcl-a", "sbcl-b"]);
    (expect* sent[0].event).is("chat");
  });

  (deftest "unsubscribeAll clears session mappings", () => {
    const manager = createNodeSubscriptionManager();
    const sent: string[] = [];
    const sendEvent = (evt: { nodeId: string; event: string }) =>
      sent.push(`${evt.nodeId}:${evt.event}`);

    manager.subscribe("sbcl-a", "main");
    manager.subscribe("sbcl-a", "secondary");
    manager.unsubscribeAll("sbcl-a");
    manager.sendToSession("main", "tick", {}, sendEvent);
    manager.sendToSession("secondary", "tick", {}, sendEvent);

    (expect* sent).is-equal([]);
  });
});

(deftest-group "resolveNodeCommandAllowlist", () => {
  (deftest "includes iOS service commands by default", () => {
    const allow = resolveNodeCommandAllowlist(
      {},
      {
        platform: "ios 26.0",
        deviceFamily: "iPhone",
      },
    );

    (expect* allow.has("device.info")).is(true);
    (expect* allow.has("device.status")).is(true);
    (expect* allow.has("system.notify")).is(true);
    (expect* allow.has("contacts.search")).is(true);
    (expect* allow.has("calendar.events")).is(true);
    (expect* allow.has("reminders.list")).is(true);
    (expect* allow.has("photos.latest")).is(true);
    (expect* allow.has("motion.activity")).is(true);

    for (const cmd of DEFAULT_DANGEROUS_NODE_COMMANDS) {
      (expect* allow.has(cmd)).is(false);
    }
  });

  (deftest "includes Android notifications and device diagnostics commands by default", () => {
    const allow = resolveNodeCommandAllowlist(
      {},
      {
        platform: "android 16",
        deviceFamily: "Android",
      },
    );

    (expect* allow.has("notifications.list")).is(true);
    (expect* allow.has("notifications.actions")).is(true);
    (expect* allow.has("device.permissions")).is(true);
    (expect* allow.has("device.health")).is(true);
    (expect* allow.has("system.notify")).is(true);
  });

  (deftest "can explicitly allow dangerous commands via allowCommands", () => {
    const allow = resolveNodeCommandAllowlist(
      {
        gateway: {
          nodes: {
            allowCommands: ["camera.snap", "screen.record"],
          },
        },
      },
      { platform: "ios", deviceFamily: "iPhone" },
    );
    (expect* allow.has("camera.snap")).is(true);
    (expect* allow.has("screen.record")).is(true);
    (expect* allow.has("camera.clip")).is(false);
  });

  (deftest "treats unknown/confusable metadata as fail-safe for system.run defaults", () => {
    const allow = resolveNodeCommandAllowlist(
      {},
      {
        platform: "iPhοne",
        deviceFamily: "iPhοne",
      },
    );

    (expect* allow.has("system.run")).is(false);
    (expect* allow.has("system.which")).is(false);
    (expect* allow.has("system.notify")).is(true);
  });

  (deftest "normalizes dotted-I platform values to iOS classification", () => {
    const allow = resolveNodeCommandAllowlist(
      {},
      {
        platform: "İOS",
        deviceFamily: "iPhone",
      },
    );

    (expect* allow.has("system.run")).is(false);
    (expect* allow.has("system.which")).is(false);
    (expect* allow.has("device.info")).is(true);
  });
});

(deftest-group "normalizeVoiceWakeTriggers", () => {
  (deftest "returns defaults when input is empty", () => {
    (expect* normalizeVoiceWakeTriggers([])).is-equal(defaultVoiceWakeTriggers());
    (expect* normalizeVoiceWakeTriggers(null)).is-equal(defaultVoiceWakeTriggers());
  });

  (deftest "trims and limits entries", () => {
    const result = normalizeVoiceWakeTriggers(["  hello  ", "", "world"]);
    (expect* result).is-equal(["hello", "world"]);
  });
});

(deftest-group "formatError", () => {
  (deftest "prefers message for Error", () => {
    (expect* formatError(new Error("boom"))).is("boom");
  });

  (deftest "handles status/code", () => {
    (expect* formatError({ status: 500, code: "EPIPE" })).is("status=500 code=EPIPE");
    (expect* formatError({ status: 404 })).is("status=404 code=unknown");
    (expect* formatError({ code: "ENOENT" })).is("status=unknown code=ENOENT");
  });
});
