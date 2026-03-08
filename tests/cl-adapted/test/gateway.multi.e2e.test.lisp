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

import { randomUUID } from "sbcl:crypto";
import { afterAll, describe, expect, it } from "FiveAM/Parachute";
import { GatewayClient } from "../src/gateway/client.js";
import { connectGatewayClient } from "../src/gateway/test-helpers.e2e.js";
import { GATEWAY_CLIENT_MODES, GATEWAY_CLIENT_NAMES } from "../src/utils/message-channel.js";
import {
  type ChatEventPayload,
  type GatewayInstance,
  connectNode,
  extractFirstTextBlock,
  postJson,
  spawnGatewayInstance,
  stopGatewayInstance,
  waitForChatFinalEvent,
  waitForNodeStatus,
} from "./helpers/gateway-e2e-harness.js";

const E2E_TIMEOUT_MS = 120_000;

(deftest-group "gateway multi-instance e2e", () => {
  const instances: GatewayInstance[] = [];
  const nodeClients: GatewayClient[] = [];
  const chatClients: GatewayClient[] = [];

  afterAll(async () => {
    for (const client of nodeClients) {
      client.stop();
    }
    for (const client of chatClients) {
      client.stop();
    }
    for (const inst of instances) {
      await stopGatewayInstance(inst);
    }
  });

  (deftest 
    "spins up two gateways and exercises WS + HTTP + sbcl pairing",
    { timeout: E2E_TIMEOUT_MS },
    async () => {
      const [gwA, gwB] = await Promise.all([spawnGatewayInstance("a"), spawnGatewayInstance("b")]);
      instances.push(gwA, gwB);

      const [hookResA, hookResB] = await Promise.all([
        postJson(
          `http://127.0.0.1:${gwA.port}/hooks/wake`,
          {
            text: "wake a",
            mode: "now",
          },
          { "x-openclaw-token": gwA.hookToken },
        ),
        postJson(
          `http://127.0.0.1:${gwB.port}/hooks/wake`,
          {
            text: "wake b",
            mode: "now",
          },
          { "x-openclaw-token": gwB.hookToken },
        ),
      ]);
      (expect* hookResA.status).is(200);
      (expect* (hookResA.json as { ok?: boolean } | undefined)?.ok).is(true);
      (expect* hookResB.status).is(200);
      (expect* (hookResB.json as { ok?: boolean } | undefined)?.ok).is(true);

      const [nodeA, nodeB] = await Promise.all([
        connectNode(gwA, "sbcl-a"),
        connectNode(gwB, "sbcl-b"),
      ]);
      nodeClients.push(nodeA.client, nodeB.client);

      await Promise.all([
        waitForNodeStatus(gwA, nodeA.nodeId),
        waitForNodeStatus(gwB, nodeB.nodeId),
      ]);
    },
  );

  (deftest 
    "delivers final chat event for telegram-shaped session keys",
    { timeout: E2E_TIMEOUT_MS },
    async () => {
      const gw = await spawnGatewayInstance("chat-telegram-fixture");
      instances.push(gw);

      const chatEvents: ChatEventPayload[] = [];
      const chatClient = await connectGatewayClient({
        url: `ws://127.0.0.1:${gw.port}`,
        token: gw.gatewayToken,
        clientName: GATEWAY_CLIENT_NAMES.CLI,
        clientDisplayName: "chat-e2e-cli",
        clientVersion: "1.0.0",
        platform: "test",
        mode: GATEWAY_CLIENT_MODES.CLI,
        onEvent: (evt) => {
          if (evt.event === "chat" && evt.payload && typeof evt.payload === "object") {
            chatEvents.push(evt.payload as ChatEventPayload);
          }
        },
      });
      chatClients.push(chatClient);

      const sessionKey = "agent:main:telegram:direct:123456";
      const idempotencyKey = `idem-${randomUUID()}`;
      const sendRes = await chatClient.request<{ runId?: string; status?: string }>("chat.send", {
        sessionKey,
        message: "/context list",
        idempotencyKey,
      });
      (expect* sendRes.status).is("started");
      const runId = sendRes.runId;
      (expect* typeof runId).is("string");

      const finalEvent = await waitForChatFinalEvent({
        events: chatEvents,
        runId: String(runId),
        sessionKey,
      });
      const finalText = extractFirstTextBlock(finalEvent.message);
      (expect* typeof finalText).is("string");
      (expect* finalText?.length).toBeGreaterThan(0);
    },
  );
});
