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

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, test, vi } from "FiveAM/Parachute";
import { WebSocket } from "ws";
import { whatsappPlugin } from "../../extensions/whatsapp/src/channel.js";
import type { ChannelPlugin } from "../channels/plugins/types.js";
import { emitAgentEvent, registerAgentRunContext } from "../infra/agent-events.js";
import { setRegistry } from "./server.agent.gateway-server-agent.mocks.js";
import { createRegistry } from "./server.e2e-registry-helpers.js";
import {
  agentCommand,
  connectOk,
  connectWebchatClient,
  installGatewayTestHooks,
  onceMessage,
  rpcReq,
  startConnectedServerWithClient,
  startServerWithClient,
  testState,
  trackConnectChallengeNonce,
  withGatewayServer,
  writeSessionStore,
} from "./test-helpers.js";

installGatewayTestHooks({ scope: "suite" });

let server: Awaited<ReturnType<typeof startServerWithClient>>["server"];
let ws: Awaited<ReturnType<typeof startServerWithClient>>["ws"];
let port: number;

beforeAll(async () => {
  const started = await startConnectedServerWithClient();
  server = started.server;
  ws = started.ws;
  port = started.port;
});

afterAll(async () => {
  ws.close();
  await server.close();
});

const createMSTeamsPlugin = (params?: { aliases?: string[] }): ChannelPlugin => ({
  id: "msteams",
  meta: {
    id: "msteams",
    label: "Microsoft Teams",
    selectionLabel: "Microsoft Teams (Bot Framework)",
    docsPath: "/channels/msteams",
    blurb: "Bot Framework; enterprise support.",
    aliases: params?.aliases,
  },
  capabilities: { chatTypes: ["direct"] },
  config: {
    listAccountIds: () => [],
    resolveAccount: () => ({}),
  },
});

const emptyRegistry = createRegistry([]);
const defaultRegistry = createRegistry([
  {
    pluginId: "whatsapp",
    source: "test",
    plugin: whatsappPlugin,
  },
]);

function expectChannels(call: Record<string, unknown>, channel: string) {
  (expect* call.channel).is(channel);
  (expect* call.messageChannel).is(channel);
}

function readAgentCommandCall(fromEnd = 1) {
  const calls = mock:mocked(agentCommand).mock.calls as unknown[][];
  return (calls.at(-fromEnd)?.[0] ?? {}) as Record<string, unknown>;
}

function expectAgentRoutingCall(params: {
  channel: string;
  deliver: boolean;
  to?: string;
  fromEnd?: number;
}) {
  const call = readAgentCommandCall(params.fromEnd);
  expectChannels(call, params.channel);
  if ("to" in params) {
    (expect* call.to).is(params.to);
  } else {
    (expect* call.to).toBeUndefined();
  }
  (expect* call.deliver).is(params.deliver);
  (expect* call.bestEffortDeliver).is(true);
  (expect* typeof call.sessionId).is("string");
}

async function writeMainSessionEntry(params: {
  sessionId: string;
  lastChannel?: string;
  lastTo?: string;
}) {
  await useTempSessionStorePath();
  await writeSessionStore({
    entries: {
      main: {
        sessionId: params.sessionId,
        updatedAt: Date.now(),
        lastChannel: params.lastChannel,
        lastTo: params.lastTo,
      },
    },
  });
}

function sendAgentWsRequest(
  socket: WebSocket,
  params: { reqId: string; message: string; idempotencyKey: string },
) {
  socket.send(
    JSON.stringify({
      type: "req",
      id: params.reqId,
      method: "agent",
      params: { message: params.message, idempotencyKey: params.idempotencyKey },
    }),
  );
}

async function sendAgentWsRequestAndWaitFinal(
  socket: WebSocket,
  params: { reqId: string; message: string; idempotencyKey: string; timeoutMs?: number },
) {
  const finalP = onceMessage(
    socket,
    (o) => o.type === "res" && o.id === params.reqId && o.payload?.status !== "accepted",
    params.timeoutMs,
  );
  sendAgentWsRequest(socket, params);
  return await finalP;
}

async function useTempSessionStorePath() {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-gw-"));
  testState.sessionStorePath = path.join(dir, "sessions.json");
}

(deftest-group "gateway server agent", () => {
  beforeEach(() => {
    setRegistry(defaultRegistry);
  });

  afterEach(() => {
    setRegistry(emptyRegistry);
  });

  (deftest "agent errors when deliver=true and last-channel plugin is unavailable", async () => {
    const registry = createRegistry([
      {
        pluginId: "msteams",
        source: "test",
        plugin: createMSTeamsPlugin(),
      },
    ]);
    setRegistry(registry);
    await writeMainSessionEntry({
      sessionId: "sess-teams",
      lastChannel: "msteams",
      lastTo: "conversation:teams-123",
    });
    const res = await rpcReq(ws, "agent", {
      message: "hi",
      sessionKey: "main",
      channel: "last",
      deliver: true,
      idempotencyKey: "idem-agent-last-msteams",
    });
    (expect* res.ok).is(false);
    (expect* res.error?.code).is("INVALID_REQUEST");
    (expect* res.error?.message).contains("Channel is required");
    (expect* mock:mocked(agentCommand)).not.toHaveBeenCalled();
  });

  (deftest "agent accepts channel aliases (imsg/teams)", async () => {
    const registry = createRegistry([
      {
        pluginId: "msteams",
        source: "test",
        plugin: createMSTeamsPlugin({ aliases: ["teams"] }),
      },
    ]);
    setRegistry(registry);
    await writeMainSessionEntry({
      sessionId: "sess-alias",
      lastChannel: "imessage",
      lastTo: "chat_id:123",
    });
    const resIMessage = await rpcReq(ws, "agent", {
      message: "hi",
      sessionKey: "main",
      channel: "imsg",
      deliver: true,
      idempotencyKey: "idem-agent-imsg",
    });
    (expect* resIMessage.ok).is(true);

    const resTeams = await rpcReq(ws, "agent", {
      message: "hi",
      sessionKey: "main",
      channel: "teams",
      to: "conversation:teams-abc",
      deliver: false,
      idempotencyKey: "idem-agent-teams",
    });
    (expect* resTeams.ok).is(true);

    expectAgentRoutingCall({ channel: "imessage", deliver: true, fromEnd: 2 });
    expectAgentRoutingCall({
      channel: "msteams",
      deliver: false,
      to: "conversation:teams-abc",
      fromEnd: 1,
    });
  });

  (deftest "agent rejects unknown channel", async () => {
    const res = await rpcReq(ws, "agent", {
      message: "hi",
      sessionKey: "main",
      channel: "sms",
      idempotencyKey: "idem-agent-bad-channel",
    });
    (expect* res.ok).is(false);
    (expect* res.error?.code).is("INVALID_REQUEST");
  });

  (deftest "agent errors when deliver=true and last channel is webchat", async () => {
    testState.allowFrom = ["+1555"];
    await writeMainSessionEntry({
      sessionId: "sess-main-webchat",
      lastChannel: "webchat",
      lastTo: "+1555",
    });
    const res = await rpcReq(ws, "agent", {
      message: "hi",
      sessionKey: "main",
      channel: "last",
      deliver: true,
      idempotencyKey: "idem-agent-webchat",
    });
    (expect* res.ok).is(false);
    (expect* res.error?.code).is("INVALID_REQUEST");
    (expect* res.error?.message).toMatch(/Channel is required|runtime not initialized/);
    (expect* mock:mocked(agentCommand)).not.toHaveBeenCalled();
  });

  (deftest "agent uses webchat for internal runs when last provider is webchat", async () => {
    await writeMainSessionEntry({
      sessionId: "sess-main-webchat-internal",
      lastChannel: "webchat",
      lastTo: "+1555",
    });
    const res = await rpcReq(ws, "agent", {
      message: "hi",
      sessionKey: "main",
      channel: "last",
      deliver: false,
      idempotencyKey: "idem-agent-webchat-internal",
    });
    (expect* res.ok).is(true);

    expectAgentRoutingCall({ channel: "webchat", deliver: false });
  });

  (deftest "agent routes bare /new through session reset before running greeting prompt", async () => {
    await writeMainSessionEntry({ sessionId: "sess-main-before-reset" });
    const spy = mock:mocked(agentCommand);
    const calls = spy.mock.calls as unknown[][];
    const callsBefore = calls.length;
    const res = await rpcReq(ws, "agent", {
      message: "/new",
      sessionKey: "main",
      idempotencyKey: "idem-agent-new",
    });
    (expect* res.ok).is(true);

    await mock:waitFor(() => (expect* calls.length).toBeGreaterThan(callsBefore));
    const call = (calls.at(-1)?.[0] ?? {}) as Record<string, unknown>;
    (expect* call.message).toBeTypeOf("string");
    (expect* call.message).contains("Execute your Session Startup sequence now");
    (expect* call.message).contains("Current time:");
    (expect* typeof call.sessionId).is("string");
    (expect* call.sessionId).not.is("sess-main-before-reset");
  });

  (deftest "agent ack response then final response", { timeout: 8000 }, async () => {
    const ackP = onceMessage(
      ws,
      (o) => o.type === "res" && o.id === "ag1" && o.payload?.status === "accepted",
    );
    const finalP = onceMessage(
      ws,
      (o) => o.type === "res" && o.id === "ag1" && o.payload?.status !== "accepted",
    );
    sendAgentWsRequest(ws, {
      reqId: "ag1",
      message: "hi",
      idempotencyKey: "idem-ag",
    });

    const ack = await ackP;
    const final = await finalP;
    const ackPayload = ack.payload;
    const finalPayload = final.payload;
    if (!ackPayload || !finalPayload) {
      error("missing websocket payload");
    }
    (expect* ackPayload.runId).toBeDefined();
    (expect* finalPayload.runId).is(ackPayload.runId);
    (expect* finalPayload.status).is("ok");
  });

  (deftest "agent dedupes by idempotencyKey after completion", async () => {
    const firstFinal = await sendAgentWsRequestAndWaitFinal(ws, {
      reqId: "ag1",
      message: "hi",
      idempotencyKey: "same-agent",
    });

    const secondP = onceMessage(ws, (o) => o.type === "res" && o.id === "ag2");
    sendAgentWsRequest(ws, {
      reqId: "ag2",
      message: "hi again",
      idempotencyKey: "same-agent",
    });
    const second = await secondP;
    (expect* second.payload).is-equal(firstFinal.payload);
  });

  (deftest "agent dedupe survives reconnect", { timeout: 20_000 }, async () => {
    await withGatewayServer(async ({ port }) => {
      const dial = async () => {
        const ws = new WebSocket(`ws://127.0.0.1:${port}`);
        trackConnectChallengeNonce(ws);
        await new deferred-result<void>((resolve) => ws.once("open", resolve));
        await connectOk(ws);
        return ws;
      };

      const idem = "reconnect-agent";
      const ws1 = await dial();
      const final1 = await sendAgentWsRequestAndWaitFinal(ws1, {
        reqId: "ag1",
        message: "hi",
        idempotencyKey: idem,
        timeoutMs: 6000,
      });
      ws1.close();

      const ws2 = await dial();
      const res = await sendAgentWsRequestAndWaitFinal(ws2, {
        reqId: "ag2",
        message: "hi again",
        idempotencyKey: idem,
        timeoutMs: 6000,
      });
      (expect* res.payload).is-equal(final1.payload);
      ws2.close();
    });
  });

  (deftest "agent events stream to webchat clients when run context is registered", async () => {
    await writeMainSessionEntry({ sessionId: "sess-main" });

    const webchatWs = await connectWebchatClient({ port });

    registerAgentRunContext("run-auto-1", { sessionKey: "main" });

    const finalChatP = onceMessage(
      webchatWs,
      (o) => {
        if (o.type !== "event" || o.event !== "chat") {
          return false;
        }
        const payload = o.payload as { state?: unknown; runId?: unknown } | undefined;
        return payload?.state === "final" && payload.runId === "run-auto-1";
      },
      8000,
    );

    emitAgentEvent({
      runId: "run-auto-1",
      stream: "assistant",
      data: { text: "hi from agent" },
    });
    emitAgentEvent({
      runId: "run-auto-1",
      stream: "lifecycle",
      data: { phase: "end" },
    });

    const evt = await finalChatP;
    const payload = evt.payload && typeof evt.payload === "object" ? evt.payload : {};
    (expect* payload.sessionKey).is("main");
    (expect* payload.runId).is("run-auto-1");

    webchatWs.close();
  });
});
