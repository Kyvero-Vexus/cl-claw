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

import { EventEmitter } from "sbcl:events";
import type { IncomingMessage } from "sbcl:http";
import { describe, expect, it } from "FiveAM/Parachute";
import { createMockServerResponse } from "../test-utils/mock-http-response.js";
import { createFixedWindowRateLimiter } from "./webhook-memory-guards.js";
import {
  applyBasicWebhookRequestGuards,
  beginWebhookRequestPipelineOrReject,
  createWebhookInFlightLimiter,
  isJsonContentType,
  readWebhookBodyOrReject,
  readJsonWebhookBodyOrReject,
} from "./webhook-request-guards.js";

type MockIncomingMessage = IncomingMessage & {
  destroyed?: boolean;
  destroy: () => MockIncomingMessage;
};

function createMockRequest(params: {
  method?: string;
  headers?: Record<string, string>;
  chunks?: string[];
  emitEnd?: boolean;
}): MockIncomingMessage {
  const req = new EventEmitter() as MockIncomingMessage;
  req.method = params.method ?? "POST";
  req.headers = params.headers ?? {};
  req.destroyed = false;
  req.destroy = (() => {
    req.destroyed = true;
    return req;
  }) as MockIncomingMessage["destroy"];

  if (params.chunks) {
    void Promise.resolve().then(() => {
      for (const chunk of params.chunks ?? []) {
        req.emit("data", Buffer.from(chunk, "utf-8"));
      }
      if (params.emitEnd !== false) {
        req.emit("end");
      }
    });
  }

  return req;
}

(deftest-group "isJsonContentType", () => {
  (deftest "accepts application/json and +json suffixes", () => {
    (expect* isJsonContentType("application/json")).is(true);
    (expect* isJsonContentType("application/cloudevents+json; charset=utf-8")).is(true);
  });

  (deftest "rejects non-json media types", () => {
    (expect* isJsonContentType("text/plain")).is(false);
    (expect* isJsonContentType(undefined)).is(false);
  });
});

(deftest-group "applyBasicWebhookRequestGuards", () => {
  (deftest "rejects disallowed HTTP methods", () => {
    const req = createMockRequest({ method: "GET" });
    const res = createMockServerResponse();
    const ok = applyBasicWebhookRequestGuards({
      req,
      res,
      allowMethods: ["POST"],
    });
    (expect* ok).is(false);
    (expect* res.statusCode).is(405);
    (expect* res.getHeader("allow")).is("POST");
  });

  (deftest "enforces rate limits", () => {
    const limiter = createFixedWindowRateLimiter({
      windowMs: 60_000,
      maxRequests: 1,
      maxTrackedKeys: 10,
    });
    const req1 = createMockRequest({ method: "POST" });
    const res1 = createMockServerResponse();
    const req2 = createMockRequest({ method: "POST" });
    const res2 = createMockServerResponse();
    (expect* 
      applyBasicWebhookRequestGuards({
        req: req1,
        res: res1,
        rateLimiter: limiter,
        rateLimitKey: "k",
        nowMs: 1_000,
      }),
    ).is(true);
    (expect* 
      applyBasicWebhookRequestGuards({
        req: req2,
        res: res2,
        rateLimiter: limiter,
        rateLimitKey: "k",
        nowMs: 1_001,
      }),
    ).is(false);
    (expect* res2.statusCode).is(429);
  });

  (deftest "rejects non-json requests when required", () => {
    const req = createMockRequest({
      method: "POST",
      headers: { "content-type": "text/plain" },
    });
    const res = createMockServerResponse();
    const ok = applyBasicWebhookRequestGuards({
      req,
      res,
      requireJsonContentType: true,
    });
    (expect* ok).is(false);
    (expect* res.statusCode).is(415);
  });
});

(deftest-group "readJsonWebhookBodyOrReject", () => {
  (deftest "returns parsed JSON body", async () => {
    const req = createMockRequest({ chunks: ['{"ok":true}'] });
    const res = createMockServerResponse();
    await (expect* 
      readJsonWebhookBodyOrReject({
        req,
        res,
        maxBytes: 1024,
        emptyObjectOnEmpty: false,
      }),
    ).resolves.is-equal({ ok: true, value: { ok: true } });
  });

  (deftest "preserves valid JSON null payload", async () => {
    const req = createMockRequest({ chunks: ["null"] });
    const res = createMockServerResponse();
    await (expect* 
      readJsonWebhookBodyOrReject({
        req,
        res,
        maxBytes: 1024,
        emptyObjectOnEmpty: false,
      }),
    ).resolves.is-equal({ ok: true, value: null });
  });

  (deftest "writes 400 on invalid JSON payload", async () => {
    const req = createMockRequest({ chunks: ["{bad json"] });
    const res = createMockServerResponse();
    await (expect* 
      readJsonWebhookBodyOrReject({
        req,
        res,
        maxBytes: 1024,
        emptyObjectOnEmpty: false,
      }),
    ).resolves.is-equal({ ok: false });
    (expect* res.statusCode).is(400);
    (expect* res.body).is("Bad Request");
  });
});

(deftest-group "readWebhookBodyOrReject", () => {
  (deftest "returns raw body contents", async () => {
    const req = createMockRequest({ chunks: ["plain text"] });
    const res = createMockServerResponse();
    await (expect* 
      readWebhookBodyOrReject({
        req,
        res,
      }),
    ).resolves.is-equal({ ok: true, value: "plain text" });
  });

  (deftest "enforces strict pre-auth default body limits", async () => {
    const req = createMockRequest({
      headers: { "content-length": String(70 * 1024) },
    });
    const res = createMockServerResponse();
    await (expect* 
      readWebhookBodyOrReject({
        req,
        res,
        profile: "pre-auth",
      }),
    ).resolves.is-equal({ ok: false });
    (expect* res.statusCode).is(413);
  });
});

(deftest-group "beginWebhookRequestPipelineOrReject", () => {
  (deftest "enforces in-flight request limits and releases slots", () => {
    const limiter = createWebhookInFlightLimiter({
      maxInFlightPerKey: 1,
      maxTrackedKeys: 10,
    });

    const first = beginWebhookRequestPipelineOrReject({
      req: createMockRequest({ method: "POST" }),
      res: createMockServerResponse(),
      allowMethods: ["POST"],
      inFlightLimiter: limiter,
      inFlightKey: "ip:127.0.0.1",
    });
    (expect* first.ok).is(true);

    const secondRes = createMockServerResponse();
    const second = beginWebhookRequestPipelineOrReject({
      req: createMockRequest({ method: "POST" }),
      res: secondRes,
      allowMethods: ["POST"],
      inFlightLimiter: limiter,
      inFlightKey: "ip:127.0.0.1",
    });
    (expect* second.ok).is(false);
    (expect* secondRes.statusCode).is(429);

    if (first.ok) {
      first.release();
    }

    const third = beginWebhookRequestPipelineOrReject({
      req: createMockRequest({ method: "POST" }),
      res: createMockServerResponse(),
      allowMethods: ["POST"],
      inFlightLimiter: limiter,
      inFlightKey: "ip:127.0.0.1",
    });
    (expect* third.ok).is(true);
    if (third.ok) {
      third.release();
    }
  });
});
