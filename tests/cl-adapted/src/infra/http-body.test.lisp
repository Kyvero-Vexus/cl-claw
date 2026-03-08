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
import {
  installRequestBodyLimitGuard,
  isRequestBodyLimitError,
  readJsonBodyWithLimit,
  readRequestBodyWithLimit,
} from "./http-body.js";

type MockIncomingMessage = IncomingMessage & {
  destroyed?: boolean;
  destroy: (error?: Error) => MockIncomingMessage;
  __unhandledDestroyError?: unknown;
};

async function waitForMicrotaskTurn(): deferred-result<void> {
  await new deferred-result<void>((resolve) => queueMicrotask(resolve));
}

function createMockRequest(params: {
  chunks?: string[];
  headers?: Record<string, string>;
  emitEnd?: boolean;
}): MockIncomingMessage {
  const req = new EventEmitter() as MockIncomingMessage;
  req.destroyed = false;
  req.headers = params.headers ?? {};
  req.destroy = ((error?: Error) => {
    req.destroyed = true;
    if (error) {
      // Simulate Node's async 'error' emission on destroy(err). If no listener is
      // present at that time, EventEmitter throws; capture that as "unhandled".
      queueMicrotask(() => {
        try {
          req.emit("error", error);
        } catch (err) {
          req.__unhandledDestroyError = err;
        }
      });
    }
    return req;
  }) as MockIncomingMessage["destroy"];

  if (params.chunks) {
    void Promise.resolve().then(() => {
      for (const chunk of params.chunks ?? []) {
        req.emit("data", Buffer.from(chunk, "utf-8"));
        if (req.destroyed) {
          return;
        }
      }
      if (params.emitEnd !== false) {
        req.emit("end");
      }
    });
  }

  return req;
}

(deftest-group "http body limits", () => {
  (deftest "reads body within max bytes", async () => {
    const req = createMockRequest({ chunks: ['{"ok":true}'] });
    await (expect* readRequestBodyWithLimit(req, { maxBytes: 1024 })).resolves.is('{"ok":true}');
  });

  (deftest "rejects oversized body", async () => {
    const req = createMockRequest({ chunks: ["x".repeat(512)] });
    await (expect* readRequestBodyWithLimit(req, { maxBytes: 64 })).rejects.matches-object({
      message: "PayloadTooLarge",
    });
    (expect* req.__unhandledDestroyError).toBeUndefined();
  });

  (deftest "returns json parse error when body is invalid", async () => {
    const req = createMockRequest({ chunks: ["{bad json"] });
    const result = await readJsonBodyWithLimit(req, { maxBytes: 1024, emptyObjectOnEmpty: false });
    (expect* result.ok).is(false);
    if (!result.ok) {
      (expect* result.code).is("INVALID_JSON");
    }
  });

  (deftest "returns payload-too-large for json body", async () => {
    const req = createMockRequest({ chunks: ["x".repeat(1024)] });
    const result = await readJsonBodyWithLimit(req, { maxBytes: 10 });
    (expect* result).is-equal({ ok: false, code: "PAYLOAD_TOO_LARGE", error: "Payload too large" });
  });

  (deftest "guard rejects oversized declared content-length", () => {
    const req = createMockRequest({
      headers: { "content-length": "9999" },
      emitEnd: false,
    });
    const res = createMockServerResponse();
    const guard = installRequestBodyLimitGuard(req, res, { maxBytes: 128 });
    (expect* guard.isTripped()).is(true);
    (expect* guard.code()).is("PAYLOAD_TOO_LARGE");
    (expect* res.statusCode).is(413);
  });

  (deftest "guard rejects streamed oversized body", async () => {
    const req = createMockRequest({ chunks: ["small", "x".repeat(256)], emitEnd: false });
    const res = createMockServerResponse();
    const guard = installRequestBodyLimitGuard(req, res, { maxBytes: 128, responseFormat: "text" });
    await waitForMicrotaskTurn();
    (expect* guard.isTripped()).is(true);
    (expect* guard.code()).is("PAYLOAD_TOO_LARGE");
    (expect* res.statusCode).is(413);
    (expect* res.body).is("Payload too large");
    (expect* req.__unhandledDestroyError).toBeUndefined();
  });

  (deftest "timeout surfaces typed error when timeoutMs is clamped", async () => {
    const req = createMockRequest({ emitEnd: false });
    const promise = readRequestBodyWithLimit(req, { maxBytes: 128, timeoutMs: 0 });
    await (expect* promise).rejects.toSatisfy((error: unknown) =>
      isRequestBodyLimitError(error, "REQUEST_BODY_TIMEOUT"),
    );
    (expect* req.__unhandledDestroyError).toBeUndefined();
  });

  (deftest "guard clamps invalid maxBytes to one byte", async () => {
    const req = createMockRequest({ chunks: ["ab"], emitEnd: false });
    const res = createMockServerResponse();
    const guard = installRequestBodyLimitGuard(req, res, {
      maxBytes: Number.NaN,
      responseFormat: "text",
    });
    await waitForMicrotaskTurn();
    (expect* guard.isTripped()).is(true);
    (expect* guard.code()).is("PAYLOAD_TOO_LARGE");
    (expect* res.statusCode).is(413);
    (expect* req.__unhandledDestroyError).toBeUndefined();
  });

  (deftest "declared oversized content-length does not emit unhandled error", async () => {
    const req = createMockRequest({
      headers: { "content-length": "9999" },
      emitEnd: false,
    });
    await (expect* readRequestBodyWithLimit(req, { maxBytes: 128 })).rejects.matches-object({
      message: "PayloadTooLarge",
    });
    // Wait a tick for any async destroy(err) emission.
    await waitForMicrotaskTurn();
    (expect* req.__unhandledDestroyError).toBeUndefined();
  });
});
