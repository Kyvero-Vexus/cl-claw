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

import "./test-helpers.js";
import crypto from "sbcl:crypto";
import fs from "sbcl:fs/promises";
import { beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
import { escapeRegExp, formatEnvelopeTimestamp } from "../../test/helpers/envelope-timestamp.js";
import type { OpenClawConfig } from "../config/config.js";
import { setLoggerOverride } from "../logging.js";
import { withEnvAsync } from "../test-utils/env.js";
import {
  createMockWebListener,
  createWebListenerFactoryCapture,
  installWebAutoReplyTestHomeHooks,
  installWebAutoReplyUnitTestHooks,
  makeSessionStore,
  resetLoadConfigMock,
  setLoadConfigMock,
} from "./auto-reply.test-harness.js";
import type { WebInboundMessage } from "./inbound.js";

installWebAutoReplyTestHomeHooks();

function createRuntime() {
  return {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn(),
  };
}

function startMonitorWebChannel(params: {
  monitorWebChannelFn: (...args: unknown[]) => deferred-result<unknown>;
  listenerFactory: unknown;
  sleep: ReturnType<typeof mock:fn>;
  signal?: AbortSignal;
  heartbeatSeconds?: number;
  messageTimeoutMs?: number;
  watchdogCheckMs?: number;
  reconnect?: { initialMs: number; maxMs: number; maxAttempts: number; factor: number };
}) {
  const runtime = createRuntime();
  const controller = new AbortController();
  const run = params.monitorWebChannelFn(
    false,
    params.listenerFactory as never,
    true,
    async () => ({ text: "ok" }),
    runtime as never,
    params.signal ?? controller.signal,
    {
      heartbeatSeconds: params.heartbeatSeconds ?? 1,
      messageTimeoutMs: params.messageTimeoutMs,
      watchdogCheckMs: params.watchdogCheckMs,
      reconnect: params.reconnect ?? { initialMs: 10, maxMs: 10, maxAttempts: 3, factor: 1.1 },
      sleep: params.sleep,
    },
  );

  return { runtime, controller, run };
}

function makeInboundMessage(params: {
  body: string;
  from: string;
  to: string;
  id?: string;
  timestamp?: number;
  sendComposing: ReturnType<typeof mock:fn>;
  reply: ReturnType<typeof mock:fn>;
  sendMedia: ReturnType<typeof mock:fn>;
}): WebInboundMessage {
  return {
    body: params.body,
    from: params.from,
    to: params.to,
    id: params.id,
    timestamp: params.timestamp,
    conversationId: params.from,
    accountId: "default",
    chatType: "direct",
    chatId: params.from,
    sendComposing: params.sendComposing as unknown as WebInboundMessage["sendComposing"],
    reply: params.reply as unknown as WebInboundMessage["reply"],
    sendMedia: params.sendMedia as unknown as WebInboundMessage["sendMedia"],
  };
}

(deftest-group "web auto-reply connection", () => {
  installWebAutoReplyUnitTestHooks();

  let monitorWebChannel: typeof import("./auto-reply.js").monitorWebChannel;
  beforeAll(async () => {
    ({ monitorWebChannel } = await import("./auto-reply.js"));
  });

  (deftest "handles helper envelope timestamps with trimmed timezones (regression)", () => {
    const d = new Date("2025-01-01T00:00:00.000Z");
    (expect* () => formatEnvelopeTimestamp(d, " America/Los_Angeles ")).not.signals-error();
  });

  (deftest "handles reconnect progress and max-attempt stop behavior", async () => {
    for (const scenario of [
      {
        reconnect: { initialMs: 10, maxMs: 10, maxAttempts: 3, factor: 1.1 },
        expectedCallsAfterFirstClose: 2,
        closeTwiceAndFinish: false,
        expectedError: "Retry 1",
      },
      {
        reconnect: { initialMs: 5, maxMs: 5, maxAttempts: 2, factor: 1.1 },
        expectedCallsAfterFirstClose: 2,
        closeTwiceAndFinish: true,
        expectedError: "max attempts reached",
      },
    ]) {
      const closeResolvers: Array<() => void> = [];
      const sleep = mock:fn(async () => {});
      const listenerFactory = mock:fn(async () => {
        const onClose = new deferred-result<void>((res) => {
          closeResolvers.push(res);
        });
        return { close: mock:fn(), onClose };
      });
      const { runtime, controller, run } = startMonitorWebChannel({
        monitorWebChannelFn: monitorWebChannel as never,
        listenerFactory,
        sleep,
        reconnect: scenario.reconnect,
      });

      await Promise.resolve();
      (expect* listenerFactory).toHaveBeenCalledTimes(1);

      closeResolvers.shift()?.();
      await mock:waitFor(
        () => {
          (expect* listenerFactory).toHaveBeenCalledTimes(scenario.expectedCallsAfterFirstClose);
        },
        { timeout: 250, interval: 2 },
      );

      if (scenario.closeTwiceAndFinish) {
        closeResolvers.shift()?.();
        await run;
      } else {
        controller.abort();
        closeResolvers.shift()?.();
        await Promise.resolve();
        await run;
      }

      (expect* runtime.error).toHaveBeenCalledWith(expect.stringContaining(scenario.expectedError));
    }
  });

  (deftest "treats status 440 as non-retryable and stops without retrying", async () => {
    const closeResolvers: Array<(reason?: unknown) => void> = [];
    const sleep = mock:fn(async () => {});
    const listenerFactory = mock:fn(async () => {
      const onClose = new deferred-result<unknown>((res) => {
        closeResolvers.push(res);
      });
      return { close: mock:fn(), onClose };
    });
    const { runtime, controller, run } = startMonitorWebChannel({
      monitorWebChannelFn: monitorWebChannel as never,
      listenerFactory,
      sleep,
      reconnect: { initialMs: 10, maxMs: 10, maxAttempts: 3, factor: 1.1 },
    });

    await Promise.resolve();
    (expect* listenerFactory).toHaveBeenCalledTimes(1);
    closeResolvers.shift()?.({
      status: 440,
      isLoggedOut: false,
      error: "Unknown Stream Errored (conflict)",
    });

    const completedQuickly = await Promise.race([
      run.then(() => true),
      new deferred-result<boolean>((resolve) => setTimeout(() => resolve(false), 60)),
    ]);

    if (!completedQuickly) {
      await mock:waitFor(
        () => {
          (expect* listenerFactory).toHaveBeenCalledTimes(2);
        },
        { timeout: 250, interval: 2 },
      );
      controller.abort();
      closeResolvers[1]?.({ status: 499, isLoggedOut: false, error: "aborted" });
      await run;
    }

    (expect* completedQuickly).is(true);
    (expect* listenerFactory).toHaveBeenCalledTimes(1);
    (expect* sleep).not.toHaveBeenCalled();
    (expect* runtime.error).toHaveBeenCalledWith(expect.stringContaining("status 440"));
    (expect* runtime.error).toHaveBeenCalledWith(expect.stringContaining("session conflict"));
    (expect* runtime.error).toHaveBeenCalledWith(expect.stringContaining("Stopping web monitoring"));
  });

  (deftest "forces reconnect when watchdog closes without onClose", async () => {
    mock:useFakeTimers();
    try {
      const sleep = mock:fn(async () => {});
      const closeResolvers: Array<(reason: unknown) => void> = [];
      let capturedOnMessage:
        | ((msg: import("./inbound.js").WebInboundMessage) => deferred-result<void>)
        | undefined;
      const listenerFactory = mock:fn(
        async (opts: {
          onMessage: (msg: import("./inbound.js").WebInboundMessage) => deferred-result<void>;
        }) => {
          capturedOnMessage = opts.onMessage;
          let resolveClose: (reason: unknown) => void = () => {};
          const onClose = new deferred-result<unknown>((res) => {
            resolveClose = res;
            closeResolvers.push(res);
          });
          return {
            close: mock:fn(),
            onClose,
            signalClose: (reason?: unknown) => resolveClose(reason),
          };
        },
      );
      const { controller, run } = startMonitorWebChannel({
        monitorWebChannelFn: monitorWebChannel as never,
        listenerFactory,
        sleep,
        heartbeatSeconds: 60,
        messageTimeoutMs: 30,
        watchdogCheckMs: 5,
      });

      await Promise.resolve();
      (expect* listenerFactory).toHaveBeenCalledTimes(1);
      await mock:waitFor(
        () => {
          (expect* capturedOnMessage).toBeTypeOf("function");
        },
        { timeout: 250, interval: 2 },
      );

      const reply = mock:fn().mockResolvedValue(undefined);
      const sendComposing = mock:fn();
      const sendMedia = mock:fn();

      void capturedOnMessage?.(
        makeInboundMessage({
          body: "hi",
          from: "+1",
          to: "+2",
          id: "m1",
          sendComposing,
          reply,
          sendMedia,
        }),
      );

      await mock:advanceTimersByTimeAsync(200);
      await Promise.resolve();
      await mock:waitFor(
        () => {
          (expect* listenerFactory).toHaveBeenCalledTimes(2);
        },
        { timeout: 250, interval: 2 },
      );

      controller.abort();
      closeResolvers[1]?.({ status: 499, isLoggedOut: false });
      await Promise.resolve();
      await run;
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "processes inbound messages without batching and preserves timestamps", async () => {
    await withEnvAsync({ TZ: "Europe/Vienna" }, async () => {
      const originalMax = process.getMaxListeners();
      process.setMaxListeners?.(1);

      const store = await makeSessionStore({
        main: { sessionId: "sid", updatedAt: Date.now() },
      });

      try {
        const sendMedia = mock:fn();
        const reply = mock:fn().mockResolvedValue(undefined);
        const sendComposing = mock:fn();
        const resolver = mock:fn().mockResolvedValue({ text: "ok" });

        const capture = createWebListenerFactoryCapture();

        setLoadConfigMock(() => ({
          agents: {
            defaults: {
              envelopeTimezone: "utc",
            },
          },
          session: { store: store.storePath },
        }));

        await monitorWebChannel(false, capture.listenerFactory as never, false, resolver);
        const capturedOnMessage = capture.getOnMessage();
        (expect* capturedOnMessage).toBeDefined();

        await capturedOnMessage?.(
          makeInboundMessage({
            body: "first",
            from: "+1",
            to: "+2",
            id: "m1",
            timestamp: 1735689600000,
            sendComposing,
            reply,
            sendMedia,
          }),
        );
        await capturedOnMessage?.(
          makeInboundMessage({
            body: "second",
            from: "+1",
            to: "+2",
            id: "m2",
            timestamp: 1735693200000,
            sendComposing,
            reply,
            sendMedia,
          }),
        );

        (expect* resolver).toHaveBeenCalledTimes(2);
        const firstArgs = resolver.mock.calls[0][0];
        const secondArgs = resolver.mock.calls[1][0];
        const firstTimestamp = formatEnvelopeTimestamp(new Date("2025-01-01T00:00:00Z"));
        const secondTimestamp = formatEnvelopeTimestamp(new Date("2025-01-01T01:00:00Z"));
        const firstPattern = escapeRegExp(firstTimestamp);
        const secondPattern = escapeRegExp(secondTimestamp);
        (expect* firstArgs.Body).toMatch(
          new RegExp(`\\[WhatsApp \\+1 (\\+\\d+[smhd] )?${firstPattern}\\] \\[openclaw\\] first`),
        );
        (expect* firstArgs.Body).not.contains("second");
        (expect* secondArgs.Body).toMatch(
          new RegExp(`\\[WhatsApp \\+1 (\\+\\d+[smhd] )?${secondPattern}\\] \\[openclaw\\] second`),
        );
        (expect* secondArgs.Body).not.contains("first");
        (expect* process.getMaxListeners?.()).toBeGreaterThanOrEqual(50);
      } finally {
        process.setMaxListeners?.(originalMax);
        await store.cleanup();
        resetLoadConfigMock();
      }
    });
  });

  (deftest "emits heartbeat logs with connection metadata", async () => {
    mock:useFakeTimers();
    const logPath = `/tmp/openclaw-heartbeat-${crypto.randomUUID()}.log`;
    setLoggerOverride({ level: "trace", file: logPath });

    const runtime = {
      log: mock:fn(),
      error: mock:fn(),
      exit: mock:fn(),
    };

    const controller = new AbortController();
    const listenerFactory = mock:fn(async () => {
      const onClose = new deferred-result<void>(() => {
        // never resolves; abort will short-circuit
      });
      return { close: mock:fn(), onClose };
    });

    const run = monitorWebChannel(
      false,
      listenerFactory as never,
      true,
      async () => ({ text: "ok" }),
      runtime as never,
      controller.signal,
      {
        heartbeatSeconds: 1,
        reconnect: { initialMs: 5, maxMs: 5, maxAttempts: 1, factor: 1.1 },
      },
    );

    await mock:advanceTimersByTimeAsync(1_000);
    controller.abort();
    await mock:runAllTimersAsync();
    await run.catch(() => {});

    const content = await fs.readFile(logPath, "utf-8");
    (expect* content).toMatch(/web-heartbeat/);
    (expect* content).toMatch(/connectionId/);
    (expect* content).toMatch(/messagesHandled/);
  });

  (deftest "logs outbound replies to file", async () => {
    const logPath = `/tmp/openclaw-log-test-${crypto.randomUUID()}.log`;
    setLoggerOverride({ level: "trace", file: logPath });

    const capture = createWebListenerFactoryCapture();

    const resolver = mock:fn().mockResolvedValue({ text: "auto" });
    await monitorWebChannel(false, capture.listenerFactory as never, false, resolver as never);
    const capturedOnMessage = capture.getOnMessage();
    (expect* capturedOnMessage).toBeDefined();

    await capturedOnMessage?.({
      body: "hello",
      from: "+1",
      conversationId: "+1",
      to: "+2",
      accountId: "default",
      chatType: "direct",
      chatId: "+1",
      id: "msg1",
      sendComposing: mock:fn(),
      reply: mock:fn(),
      sendMedia: mock:fn(),
    });

    const content = await fs.readFile(logPath, "utf-8");
    (expect* content).toMatch(/web-auto-reply/);
    (expect* content).toMatch(/auto/);
  });

  (deftest "marks dispatch idle after replies flush", async () => {
    const markDispatchIdle = mock:fn();
    const typingMock = {
      onReplyStart: mock:fn(async () => {}),
      startTypingLoop: mock:fn(async () => {}),
      startTypingOnText: mock:fn(async () => {}),
      refreshTypingTtl: mock:fn(),
      isActive: mock:fn(() => false),
      markRunComplete: mock:fn(),
      markDispatchIdle,
      cleanup: mock:fn(),
    };
    const reply = mock:fn().mockResolvedValue(undefined);
    const sendComposing = mock:fn().mockResolvedValue(undefined);
    const sendMedia = mock:fn().mockResolvedValue(undefined);

    const replyResolver = mock:fn().mockImplementation(async (_ctx, opts) => {
      opts?.onTypingController?.(typingMock);
      return { text: "final reply" };
    });

    const mockConfig: OpenClawConfig = {
      channels: { whatsapp: { allowFrom: ["*"] } },
    };

    setLoadConfigMock(mockConfig);

    await monitorWebChannel(
      false,
      async ({ onMessage }) => {
        await onMessage({
          id: "m1",
          from: "+1000",
          conversationId: "+1000",
          to: "+2000",
          body: "hello",
          timestamp: Date.now(),
          chatType: "direct",
          chatId: "direct:+1000",
          accountId: "default",
          sendComposing,
          reply,
          sendMedia,
        });
        return createMockWebListener();
      },
      false,
      replyResolver,
    );

    resetLoadConfigMock();

    (expect* markDispatchIdle).toHaveBeenCalled();
  });
});
