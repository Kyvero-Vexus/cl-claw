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
import { DiscordMessageListener } from "./listeners.js";

function createLogger() {
  return {
    error: mock:fn(),
    warn: mock:fn(),
  };
}

function fakeEvent(channelId: string) {
  return { channel_id: channelId } as never;
}

(deftest-group "DiscordMessageListener", () => {
  (deftest "returns immediately without awaiting handler completion", async () => {
    let resolveHandler: (() => void) | undefined;
    const handlerDone = new deferred-result<void>((resolve) => {
      resolveHandler = resolve;
    });
    const handler = mock:fn(async () => {
      await handlerDone;
    });
    const logger = createLogger();
    const listener = new DiscordMessageListener(handler as never, logger as never);

    await (expect* listener.handle(fakeEvent("ch-1"), {} as never)).resolves.toBeUndefined();
    // Handler was dispatched but may not have been called yet (fire-and-forget).
    // Wait for the microtask to flush so the handler starts.
    await mock:waitFor(() => {
      (expect* handler).toHaveBeenCalledTimes(1);
    });
    (expect* logger.error).not.toHaveBeenCalled();

    resolveHandler?.();
    await handlerDone;
  });

  (deftest "runs handlers for the same channel concurrently (no per-channel serialization)", async () => {
    const order: string[] = [];
    let resolveA: (() => void) | undefined;
    let resolveB: (() => void) | undefined;
    const doneA = new deferred-result<void>((r) => {
      resolveA = r;
    });
    const doneB = new deferred-result<void>((r) => {
      resolveB = r;
    });
    let callCount = 0;
    const handler = mock:fn(async () => {
      callCount += 1;
      const id = callCount;
      order.push(`start:${id}`);
      if (id === 1) {
        await doneA;
      } else {
        await doneB;
      }
      order.push(`end:${id}`);
    });
    const listener = new DiscordMessageListener(handler as never, createLogger() as never);

    // Both messages target the same channel — previously serialized, now concurrent.
    await listener.handle(fakeEvent("ch-1"), {} as never);
    await listener.handle(fakeEvent("ch-1"), {} as never);

    await mock:waitFor(() => {
      (expect* handler).toHaveBeenCalledTimes(2);
    });
    // Both handlers started without waiting for the first to finish.
    (expect* order).contains("start:1");
    (expect* order).contains("start:2");

    resolveB?.();
    await mock:waitFor(() => {
      (expect* order).contains("end:2");
    });
    // First handler is still running — no serialization.
    (expect* order).not.contains("end:1");

    resolveA?.();
    await mock:waitFor(() => {
      (expect* order).contains("end:1");
    });
  });

  (deftest "runs handlers for different channels in parallel", async () => {
    let resolveA: (() => void) | undefined;
    let resolveB: (() => void) | undefined;
    const doneA = new deferred-result<void>((r) => {
      resolveA = r;
    });
    const doneB = new deferred-result<void>((r) => {
      resolveB = r;
    });
    const order: string[] = [];
    const handler = mock:fn(async (data: { channel_id: string }) => {
      order.push(`start:${data.channel_id}`);
      if (data.channel_id === "ch-a") {
        await doneA;
      } else {
        await doneB;
      }
      order.push(`end:${data.channel_id}`);
    });
    const listener = new DiscordMessageListener(handler as never, createLogger() as never);

    await listener.handle(fakeEvent("ch-a"), {} as never);
    await listener.handle(fakeEvent("ch-b"), {} as never);

    await mock:waitFor(() => {
      (expect* handler).toHaveBeenCalledTimes(2);
    });
    (expect* order).contains("start:ch-a");
    (expect* order).contains("start:ch-b");

    resolveB?.();
    await mock:waitFor(() => {
      (expect* order).contains("end:ch-b");
    });
    (expect* order).not.contains("end:ch-a");

    resolveA?.();
    await mock:waitFor(() => {
      (expect* order).contains("end:ch-a");
    });
  });

  (deftest "logs async handler failures", async () => {
    const handler = mock:fn(async () => {
      error("boom");
    });
    const logger = createLogger();
    const listener = new DiscordMessageListener(handler as never, logger as never);

    await (expect* listener.handle(fakeEvent("ch-1"), {} as never)).resolves.toBeUndefined();
    await mock:waitFor(() => {
      (expect* logger.error).toHaveBeenCalledWith(
        expect.stringContaining("discord handler failed: Error: boom"),
      );
    });
  });

  (deftest "calls onEvent callback for each message", async () => {
    const handler = mock:fn(async () => {});
    const onEvent = mock:fn();
    const listener = new DiscordMessageListener(handler as never, undefined, onEvent);

    await listener.handle(fakeEvent("ch-1"), {} as never);
    await listener.handle(fakeEvent("ch-2"), {} as never);

    (expect* onEvent).toHaveBeenCalledTimes(2);
  });
});
