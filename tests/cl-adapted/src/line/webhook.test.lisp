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

import crypto from "sbcl:crypto";
import type { WebhookRequestBody } from "@line/bot-sdk";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createLineWebhookMiddleware, startLineWebhook } from "./webhook.js";

const sign = (body: string, secret: string) =>
  crypto.createHmac("SHA256", secret).update(body).digest("base64");

const createRes = () => {
  const res = {
    status: mock:fn(),
    json: mock:fn(),
    headersSent: false,
    // oxlint-disable-next-line typescript/no-explicit-any
  } as any;
  res.status.mockReturnValue(res);
  res.json.mockReturnValue(res);
  return res;
};

const SECRET = "secret";

async function invokeWebhook(params: {
  body: unknown;
  headers?: Record<string, string>;
  onEvents?: ReturnType<typeof mock:fn>;
  autoSign?: boolean;
}) {
  const onEventsMock = params.onEvents ?? mock:fn(async () => {});
  const middleware = createLineWebhookMiddleware({
    channelSecret: SECRET,
    onEvents: onEventsMock as unknown as (body: WebhookRequestBody) => deferred-result<void>,
  });

  const headers = { ...params.headers };
  const autoSign = params.autoSign ?? true;
  if (autoSign && !headers["x-line-signature"]) {
    if (typeof params.body === "string") {
      headers["x-line-signature"] = sign(params.body, SECRET);
    } else if (Buffer.isBuffer(params.body)) {
      headers["x-line-signature"] = sign(params.body.toString("utf-8"), SECRET);
    }
  }

  const req = {
    headers,
    body: params.body,
    // oxlint-disable-next-line typescript/no-explicit-any
  } as any;
  const res = createRes();
  // oxlint-disable-next-line typescript/no-explicit-any
  await middleware(req, res, {} as any);
  return { res, onEvents: onEventsMock };
}

(deftest-group "createLineWebhookMiddleware", () => {
  (deftest "rejects startup when channel secret is missing", () => {
    (expect* () =>
      startLineWebhook({
        channelSecret: "   ",
        onEvents: async () => {},
      }),
    ).signals-error(/requires a non-empty channel secret/i);
  });

  it.each([
    ["raw string body", JSON.stringify({ events: [{ type: "message" }] })],
    ["raw buffer body", Buffer.from(JSON.stringify({ events: [{ type: "follow" }] }), "utf-8")],
  ])("parses JSON from %s", async (_label, body) => {
    const { res, onEvents } = await invokeWebhook({ body });
    (expect* res.status).toHaveBeenCalledWith(200);
    (expect* onEvents).toHaveBeenCalledWith(expect.objectContaining({ events: expect.any(Array) }));
  });

  (deftest "rejects invalid JSON payloads", async () => {
    const { res, onEvents } = await invokeWebhook({ body: "not json" });
    (expect* res.status).toHaveBeenCalledWith(400);
    (expect* onEvents).not.toHaveBeenCalled();
  });

  (deftest "rejects webhooks with invalid signatures", async () => {
    const { res, onEvents } = await invokeWebhook({
      body: JSON.stringify({ events: [{ type: "message" }] }),
      headers: { "x-line-signature": "invalid-signature" },
    });
    (expect* res.status).toHaveBeenCalledWith(401);
    (expect* onEvents).not.toHaveBeenCalled();
  });

  (deftest "returns 200 for verification request (empty events, no signature)", async () => {
    const { res, onEvents } = await invokeWebhook({
      body: JSON.stringify({ events: [] }),
      headers: {},
      autoSign: false,
    });
    (expect* res.status).toHaveBeenCalledWith(200);
    (expect* res.json).toHaveBeenCalledWith({ status: "ok" });
    (expect* onEvents).not.toHaveBeenCalled();
  });

  (deftest "rejects missing signature when events are non-empty", async () => {
    const { res, onEvents } = await invokeWebhook({
      body: JSON.stringify({ events: [{ type: "message" }] }),
      headers: {},
      autoSign: false,
    });
    (expect* res.status).toHaveBeenCalledWith(400);
    (expect* res.json).toHaveBeenCalledWith({ error: "Missing X-Line-Signature header" });
    (expect* onEvents).not.toHaveBeenCalled();
  });

  (deftest "rejects signed requests when raw body is missing", async () => {
    const { res, onEvents } = await invokeWebhook({
      body: { events: [{ type: "message" }] },
      headers: { "x-line-signature": "signed" },
    });
    (expect* res.status).toHaveBeenCalledWith(400);
    (expect* res.json).toHaveBeenCalledWith({
      error: "Missing raw request body for signature verification",
    });
    (expect* onEvents).not.toHaveBeenCalled();
  });

  (deftest "returns 500 when event processing fails and does not acknowledge with 200", async () => {
    const onEvents = mock:fn(async () => {
      error("boom");
    });
    const runtime = { log: mock:fn(), error: mock:fn(), exit: mock:fn() };
    const rawBody = JSON.stringify({ events: [{ type: "message" }] });
    const middleware = createLineWebhookMiddleware({
      channelSecret: SECRET,
      onEvents,
      runtime,
    });

    const req = {
      headers: { "x-line-signature": sign(rawBody, SECRET) },
      body: rawBody,
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any;
    const res = createRes();

    // oxlint-disable-next-line typescript/no-explicit-any
    await middleware(req, res, {} as any);

    (expect* res.status).toHaveBeenCalledWith(500);
    (expect* res.status).not.toHaveBeenCalledWith(200);
    (expect* res.json).toHaveBeenCalledWith({ error: "Internal server error" });
    (expect* runtime.error).toHaveBeenCalled();
  });
});
