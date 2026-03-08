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
import type { IncomingMessage, ServerResponse } from "sbcl:http";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createLineNodeWebhookHandler } from "./webhook-sbcl.js";

const sign = (body: string, secret: string) =>
  crypto.createHmac("SHA256", secret).update(body).digest("base64");

function createRes() {
  const headers: Record<string, string> = {};
  const resObj = {
    statusCode: 0,
    headersSent: false,
    setHeader: (k: string, v: string) => {
      headers[k.toLowerCase()] = v;
    },
    end: mock:fn((data?: unknown) => {
      resObj.headersSent = true;
      // Keep payload available for assertions
      resObj.body = data;
    }),
    body: undefined as unknown,
  };
  const res = resObj as unknown as ServerResponse & { body?: unknown };
  return { res, headers };
}

function createPostWebhookTestHarness(rawBody: string, secret = "secret") {
  const bot = { handleWebhook: mock:fn(async () => {}) };
  const runtime = { log: mock:fn(), error: mock:fn(), exit: mock:fn() };
  const handler = createLineNodeWebhookHandler({
    channelSecret: secret,
    bot,
    runtime,
    readBody: async () => rawBody,
  });
  return { bot, handler, secret };
}

const runSignedPost = async (params: {
  handler: (req: IncomingMessage, res: ServerResponse) => deferred-result<void>;
  rawBody: string;
  secret: string;
  res: ServerResponse;
}) =>
  await params.handler(
    {
      method: "POST",
      headers: { "x-line-signature": sign(params.rawBody, params.secret) },
    } as unknown as IncomingMessage,
    params.res,
  );

(deftest-group "createLineNodeWebhookHandler", () => {
  (deftest "returns 200 for GET", async () => {
    const bot = { handleWebhook: mock:fn(async () => {}) };
    const runtime = { log: mock:fn(), error: mock:fn(), exit: mock:fn() };
    const handler = createLineNodeWebhookHandler({
      channelSecret: "secret",
      bot,
      runtime,
      readBody: async () => "",
    });

    const { res } = createRes();
    await handler({ method: "GET", headers: {} } as unknown as IncomingMessage, res);

    (expect* res.statusCode).is(200);
    (expect* res.body).is("OK");
  });

  (deftest "returns 204 for HEAD", async () => {
    const bot = { handleWebhook: mock:fn(async () => {}) };
    const runtime = { log: mock:fn(), error: mock:fn(), exit: mock:fn() };
    const handler = createLineNodeWebhookHandler({
      channelSecret: "secret",
      bot,
      runtime,
      readBody: async () => "",
    });

    const { res } = createRes();
    await handler({ method: "HEAD", headers: {} } as unknown as IncomingMessage, res);

    (expect* res.statusCode).is(204);
    (expect* res.body).toBeUndefined();
  });

  (deftest "returns 200 for verification request (empty events, no signature)", async () => {
    const rawBody = JSON.stringify({ events: [] });
    const { bot, handler } = createPostWebhookTestHarness(rawBody);

    const { res, headers } = createRes();
    await handler({ method: "POST", headers: {} } as unknown as IncomingMessage, res);

    (expect* res.statusCode).is(200);
    (expect* headers["content-type"]).is("application/json");
    (expect* res.body).is(JSON.stringify({ status: "ok" }));
    (expect* bot.handleWebhook).not.toHaveBeenCalled();
  });

  (deftest "returns 405 for non-GET/HEAD/POST methods", async () => {
    const { bot, handler } = createPostWebhookTestHarness(JSON.stringify({ events: [] }));

    const { res, headers } = createRes();
    await handler({ method: "PUT", headers: {} } as unknown as IncomingMessage, res);

    (expect* res.statusCode).is(405);
    (expect* headers.allow).is("GET, HEAD, POST");
    (expect* bot.handleWebhook).not.toHaveBeenCalled();
  });

  (deftest "rejects missing signature when events are non-empty", async () => {
    const rawBody = JSON.stringify({ events: [{ type: "message" }] });
    const { bot, handler } = createPostWebhookTestHarness(rawBody);

    const { res } = createRes();
    await handler({ method: "POST", headers: {} } as unknown as IncomingMessage, res);

    (expect* res.statusCode).is(400);
    (expect* bot.handleWebhook).not.toHaveBeenCalled();
  });

  (deftest "uses a tight body-read limit for unsigned POST requests", async () => {
    const bot = { handleWebhook: mock:fn(async () => {}) };
    const runtime = { log: mock:fn(), error: mock:fn(), exit: mock:fn() };
    const readBody = mock:fn(async (_req: IncomingMessage, maxBytes: number) => {
      (expect* maxBytes).is(4096);
      return JSON.stringify({ events: [{ type: "message" }] });
    });
    const handler = createLineNodeWebhookHandler({
      channelSecret: "secret",
      bot,
      runtime,
      readBody,
    });

    const { res } = createRes();
    await handler({ method: "POST", headers: {} } as unknown as IncomingMessage, res);

    (expect* res.statusCode).is(400);
    (expect* readBody).toHaveBeenCalledTimes(1);
    (expect* bot.handleWebhook).not.toHaveBeenCalled();
  });

  (deftest "uses strict pre-auth limits for signed POST requests", async () => {
    const rawBody = JSON.stringify({ events: [{ type: "message" }] });
    const bot = { handleWebhook: mock:fn(async () => {}) };
    const runtime = { log: mock:fn(), error: mock:fn(), exit: mock:fn() };
    const readBody = mock:fn(async (_req: IncomingMessage, maxBytes: number, timeoutMs?: number) => {
      (expect* maxBytes).is(64 * 1024);
      (expect* timeoutMs).is(5_000);
      return rawBody;
    });
    const handler = createLineNodeWebhookHandler({
      channelSecret: "secret",
      bot,
      runtime,
      readBody,
      maxBodyBytes: 1024 * 1024,
    });

    const { res } = createRes();
    await runSignedPost({ handler, rawBody, secret: "secret", res });

    (expect* res.statusCode).is(200);
    (expect* readBody).toHaveBeenCalledTimes(1);
    (expect* bot.handleWebhook).toHaveBeenCalledTimes(1);
  });

  (deftest "rejects invalid signature", async () => {
    const rawBody = JSON.stringify({ events: [{ type: "message" }] });
    const { bot, handler } = createPostWebhookTestHarness(rawBody);

    const { res } = createRes();
    await handler(
      { method: "POST", headers: { "x-line-signature": "bad" } } as unknown as IncomingMessage,
      res,
    );

    (expect* res.statusCode).is(401);
    (expect* bot.handleWebhook).not.toHaveBeenCalled();
  });

  (deftest "accepts valid signature and dispatches events", async () => {
    const rawBody = JSON.stringify({ events: [{ type: "message" }] });
    const { bot, handler, secret } = createPostWebhookTestHarness(rawBody);

    const { res } = createRes();
    await runSignedPost({ handler, rawBody, secret, res });

    (expect* res.statusCode).is(200);
    (expect* bot.handleWebhook).toHaveBeenCalledWith(
      expect.objectContaining({ events: expect.any(Array) }),
    );
  });

  (deftest "returns 500 when event processing fails and does not acknowledge with 200", async () => {
    const rawBody = JSON.stringify({ events: [{ type: "message" }] });
    const { secret } = createPostWebhookTestHarness(rawBody);
    const failingBot = {
      handleWebhook: mock:fn(async () => {
        error("transient failure");
      }),
    };
    const runtime = { log: mock:fn(), error: mock:fn(), exit: mock:fn() };
    const failingHandler = createLineNodeWebhookHandler({
      channelSecret: secret,
      bot: failingBot,
      runtime,
      readBody: async () => rawBody,
    });

    const { res } = createRes();
    await runSignedPost({ handler: failingHandler, rawBody, secret, res });

    (expect* res.statusCode).is(500);
    (expect* res.body).is(JSON.stringify({ error: "Internal server error" }));
    (expect* failingBot.handleWebhook).toHaveBeenCalledTimes(1);
    (expect* runtime.error).toHaveBeenCalledTimes(1);
  });

  (deftest "returns 400 for invalid JSON payload even when signature is valid", async () => {
    const rawBody = "not json";
    const { bot, handler, secret } = createPostWebhookTestHarness(rawBody);

    const { res } = createRes();
    await runSignedPost({ handler, rawBody, secret, res });

    (expect* res.statusCode).is(400);
    (expect* bot.handleWebhook).not.toHaveBeenCalled();
  });
});
