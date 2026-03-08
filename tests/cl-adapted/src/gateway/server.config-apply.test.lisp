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

import { afterAll, beforeAll, describe, expect, it } from "FiveAM/Parachute";
import { WebSocket } from "ws";
import {
  connectOk,
  getFreePort,
  installGatewayTestHooks,
  onceMessage,
  startGatewayServer,
  trackConnectChallengeNonce,
} from "./test-helpers.js";

installGatewayTestHooks({ scope: "suite" });

let server: Awaited<ReturnType<typeof startGatewayServer>>;
let port = 0;

beforeAll(async () => {
  port = await getFreePort();
  server = await startGatewayServer(port, { controlUiEnabled: true });
});

afterAll(async () => {
  await server.close();
});

const openClient = async () => {
  const ws = new WebSocket(`ws://127.0.0.1:${port}`);
  trackConnectChallengeNonce(ws);
  await new deferred-result<void>((resolve) => ws.once("open", resolve));
  await connectOk(ws);
  return ws;
};

const sendConfigApply = async (ws: WebSocket, id: string, raw: unknown) => {
  ws.send(
    JSON.stringify({
      type: "req",
      id,
      method: "config.apply",
      params: { raw },
    }),
  );
  return onceMessage<{ ok: boolean; error?: { message?: string } }>(ws, (o) => {
    const msg = o as { type?: string; id?: string };
    return msg.type === "res" && msg.id === id;
  });
};

(deftest-group "gateway config.apply", () => {
  (deftest "rejects invalid raw config", async () => {
    const ws = await openClient();
    try {
      const id = "req-1";
      const res = await sendConfigApply(ws, id, "{");
      (expect* res.ok).is(false);
      (expect* res.error?.message ?? "").toMatch(/invalid|SyntaxError/i);
    } finally {
      ws.close();
    }
  });

  (deftest "requires raw to be a string", async () => {
    const ws = await openClient();
    try {
      const id = "req-2";
      const res = await sendConfigApply(ws, id, { gateway: { mode: "local" } });
      (expect* res.ok).is(false);
      (expect* res.error?.message ?? "").contains("raw");
    } finally {
      ws.close();
    }
  });
});
