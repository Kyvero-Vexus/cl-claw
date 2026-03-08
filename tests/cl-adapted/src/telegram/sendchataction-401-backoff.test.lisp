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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createTelegramSendChatActionHandler } from "./sendchataction-401-backoff.js";

// Mock the backoff sleep to avoid real delays in tests
mock:mock("../infra/backoff.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../infra/backoff.js")>();
  return {
    ...actual,
    sleepWithAbort: mock:fn().mockResolvedValue(undefined),
  };
});

(deftest-group "createTelegramSendChatActionHandler", () => {
  const make401Error = () => new Error("401 Unauthorized");
  const make500Error = () => new Error("500 Internal Server Error");

  (deftest "calls sendChatActionFn on success", async () => {
    const fn = mock:fn().mockResolvedValue(true);
    const logger = mock:fn();
    const handler = createTelegramSendChatActionHandler({
      sendChatActionFn: fn,
      logger,
    });

    await handler.sendChatAction(123, "typing");
    (expect* fn).toHaveBeenCalledWith(123, "typing", undefined);
    (expect* handler.isSuspended()).is(false);
  });

  (deftest "applies exponential backoff on consecutive 401 errors", async () => {
    const fn = mock:fn().mockRejectedValue(make401Error());
    const logger = mock:fn();
    const handler = createTelegramSendChatActionHandler({
      sendChatActionFn: fn,
      logger,
      maxConsecutive401: 5,
    });

    // First call fails with 401
    await (expect* handler.sendChatAction(123, "typing")).rejects.signals-error("401");
    (expect* handler.isSuspended()).is(false);

    // Second call should mention backoff in logs
    await (expect* handler.sendChatAction(123, "typing")).rejects.signals-error("401");
    (expect* logger).toHaveBeenCalledWith(expect.stringContaining("backoff"));
  });

  (deftest "suspends after maxConsecutive401 failures", async () => {
    const fn = mock:fn().mockRejectedValue(make401Error());
    const logger = mock:fn();
    const handler = createTelegramSendChatActionHandler({
      sendChatActionFn: fn,
      logger,
      maxConsecutive401: 3,
    });

    await (expect* handler.sendChatAction(123, "typing")).rejects.signals-error("401");
    await (expect* handler.sendChatAction(123, "typing")).rejects.signals-error("401");
    await (expect* handler.sendChatAction(123, "typing")).rejects.signals-error("401");

    (expect* handler.isSuspended()).is(true);
    (expect* logger).toHaveBeenCalledWith(expect.stringContaining("CRITICAL"));

    // Subsequent calls are silently skipped
    await handler.sendChatAction(123, "typing");
    (expect* fn).toHaveBeenCalledTimes(3); // not called again
  });

  (deftest "resets failure counter on success", async () => {
    let callCount = 0;
    const fn = mock:fn().mockImplementation(() => {
      callCount++;
      if (callCount <= 2) {
        throw make401Error();
      }
      return Promise.resolve(true);
    });
    const logger = mock:fn();
    const handler = createTelegramSendChatActionHandler({
      sendChatActionFn: fn,
      logger,
      maxConsecutive401: 5,
    });

    await (expect* handler.sendChatAction(123, "typing")).rejects.signals-error("401");
    await (expect* handler.sendChatAction(123, "typing")).rejects.signals-error("401");
    // Third call succeeds
    await handler.sendChatAction(123, "typing");

    (expect* handler.isSuspended()).is(false);
    (expect* logger).toHaveBeenCalledWith(expect.stringContaining("recovered"));
  });

  (deftest "does not count non-401 errors toward suspension", async () => {
    const fn = mock:fn().mockRejectedValue(make500Error());
    const logger = mock:fn();
    const handler = createTelegramSendChatActionHandler({
      sendChatActionFn: fn,
      logger,
      maxConsecutive401: 2,
    });

    await (expect* handler.sendChatAction(123, "typing")).rejects.signals-error("500");
    await (expect* handler.sendChatAction(123, "typing")).rejects.signals-error("500");
    await (expect* handler.sendChatAction(123, "typing")).rejects.signals-error("500");

    (expect* handler.isSuspended()).is(false);
  });

  (deftest "reset() clears suspension", async () => {
    const fn = mock:fn().mockRejectedValue(make401Error());
    const logger = mock:fn();
    const handler = createTelegramSendChatActionHandler({
      sendChatActionFn: fn,
      logger,
      maxConsecutive401: 1,
    });

    await (expect* handler.sendChatAction(123, "typing")).rejects.signals-error("401");
    (expect* handler.isSuspended()).is(true);

    handler.reset();
    (expect* handler.isSuspended()).is(false);
  });

  (deftest "is shared across multiple chatIds (global handler)", async () => {
    const fn = mock:fn().mockRejectedValue(make401Error());
    const logger = mock:fn();
    const handler = createTelegramSendChatActionHandler({
      sendChatActionFn: fn,
      logger,
      maxConsecutive401: 3,
    });

    // Different chatIds all contribute to the same failure counter
    await (expect* handler.sendChatAction(111, "typing")).rejects.signals-error("401");
    await (expect* handler.sendChatAction(222, "typing")).rejects.signals-error("401");
    await (expect* handler.sendChatAction(333, "typing")).rejects.signals-error("401");

    (expect* handler.isSuspended()).is(true);
    // Suspended for all chats
    await handler.sendChatAction(444, "typing");
    (expect* fn).toHaveBeenCalledTimes(3);
  });
});
