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
import {
  createDiscordHandlerParams,
  createDiscordPreflightContext,
} from "./message-handler.test-helpers.js";

const preflightDiscordMessageMock = mock:hoisted(() => mock:fn());
const processDiscordMessageMock = mock:hoisted(() => mock:fn());
const eventualReplyDeliveredMock = mock:hoisted(() => mock:fn());
type SetStatusFn = (patch: Record<string, unknown>) => void;

mock:mock("./message-handler.preflight.js", () => ({
  preflightDiscordMessage: preflightDiscordMessageMock,
}));

mock:mock("./message-handler.process.js", () => ({
  processDiscordMessage: processDiscordMessageMock,
}));

const { createDiscordMessageHandler } = await import("./message-handler.js");

function createDeferred<T = void>() {
  let resolve: (value: T | PromiseLike<T>) => void = () => {};
  const promise = new deferred-result<T>((innerResolve) => {
    resolve = innerResolve;
  });
  return { promise, resolve };
}

function createMessageData(messageId: string, channelId = "ch-1") {
  return {
    channel_id: channelId,
    author: { id: "user-1" },
    message: {
      id: messageId,
      author: { id: "user-1", bot: false },
      content: "hello",
      channel_id: channelId,
      attachments: [{ id: `att-${messageId}` }],
    },
  };
}

function createPreflightContext(channelId = "ch-1") {
  return createDiscordPreflightContext(channelId);
}

async function createLifecycleStopScenario(params: {
  createHandler: (status: SetStatusFn) => {
    handler: (data: never, opts: never) => deferred-result<void>;
    stop: () => void;
  };
}) {
  const runInFlight = createDeferred();
  processDiscordMessageMock.mockImplementation(async () => {
    await runInFlight.promise;
  });
  preflightDiscordMessageMock.mockImplementation(
    async (contextParams: { data: { channel_id: string } }) =>
      createPreflightContext(contextParams.data.channel_id),
  );

  const setStatus = mock:fn<SetStatusFn>();
  const { handler, stop } = params.createHandler(setStatus);

  await (expect* handler(createMessageData("m-1") as never, {} as never)).resolves.toBeUndefined();
  await mock:waitFor(() => {
    (expect* processDiscordMessageMock).toHaveBeenCalledTimes(1);
  });

  const callsBeforeStop = setStatus.mock.calls.length;
  stop();

  return {
    setStatus,
    callsBeforeStop,
    finish: async () => {
      runInFlight.resolve();
      await runInFlight.promise;
      await Promise.resolve();
    },
  };
}

(deftest-group "createDiscordMessageHandler queue behavior", () => {
  (deftest "resets busy counters when the handler is created", () => {
    preflightDiscordMessageMock.mockReset();
    processDiscordMessageMock.mockReset();

    const setStatus = mock:fn();
    createDiscordMessageHandler(createDiscordHandlerParams({ setStatus }));

    (expect* setStatus).toHaveBeenCalledWith(
      expect.objectContaining({
        activeRuns: 0,
        busy: false,
      }),
    );
  });

  (deftest "returns immediately and tracks busy status while queued runs execute", async () => {
    preflightDiscordMessageMock.mockReset();
    processDiscordMessageMock.mockReset();

    const firstRun = createDeferred();
    const secondRun = createDeferred();
    processDiscordMessageMock
      .mockImplementationOnce(async () => {
        await firstRun.promise;
      })
      .mockImplementationOnce(async () => {
        await secondRun.promise;
      });
    preflightDiscordMessageMock.mockImplementation(
      async (params: { data: { channel_id: string } }) =>
        createPreflightContext(params.data.channel_id),
    );

    const setStatus = mock:fn();
    const handler = createDiscordMessageHandler(createDiscordHandlerParams({ setStatus }));

    await (expect* handler(createMessageData("m-1") as never, {} as never)).resolves.toBeUndefined();

    await mock:waitFor(() => {
      (expect* processDiscordMessageMock).toHaveBeenCalledTimes(1);
    });
    (expect* setStatus).toHaveBeenCalledWith(
      expect.objectContaining({
        activeRuns: 1,
        busy: true,
      }),
    );

    await (expect* handler(createMessageData("m-2") as never, {} as never)).resolves.toBeUndefined();

    await mock:waitFor(() => {
      (expect* preflightDiscordMessageMock).toHaveBeenCalledTimes(2);
    });
    (expect* processDiscordMessageMock).toHaveBeenCalledTimes(1);

    firstRun.resolve();
    await firstRun.promise;

    await mock:waitFor(() => {
      (expect* processDiscordMessageMock).toHaveBeenCalledTimes(2);
    });

    secondRun.resolve();
    await secondRun.promise;

    await mock:waitFor(() => {
      (expect* setStatus).toHaveBeenLastCalledWith(
        expect.objectContaining({
          activeRuns: 0,
          busy: false,
        }),
      );
    });
  });

  (deftest "applies explicit inbound worker timeout to queued runs so stalled runs do not block the queue", async () => {
    mock:useFakeTimers();
    try {
      preflightDiscordMessageMock.mockReset();
      processDiscordMessageMock.mockReset();

      processDiscordMessageMock
        .mockImplementationOnce(async (ctx: { abortSignal?: AbortSignal }) => {
          await new deferred-result<void>((resolve) => {
            if (ctx.abortSignal?.aborted) {
              resolve();
              return;
            }
            ctx.abortSignal?.addEventListener("abort", () => resolve(), { once: true });
          });
        })
        .mockImplementationOnce(async () => undefined);
      preflightDiscordMessageMock.mockImplementation(
        async (params: { data: { channel_id: string } }) =>
          createPreflightContext(params.data.channel_id),
      );

      const params = createDiscordHandlerParams({ workerRunTimeoutMs: 50 });
      const handler = createDiscordMessageHandler(params);

      await (expect* 
        handler(createMessageData("m-1") as never, {} as never),
      ).resolves.toBeUndefined();
      await (expect* 
        handler(createMessageData("m-2") as never, {} as never),
      ).resolves.toBeUndefined();

      await mock:advanceTimersByTimeAsync(60);
      await mock:waitFor(() => {
        (expect* processDiscordMessageMock).toHaveBeenCalledTimes(2);
      });

      const firstCtx = processDiscordMessageMock.mock.calls[0]?.[0] as
        | { abortSignal?: AbortSignal }
        | undefined;
      (expect* firstCtx?.abortSignal?.aborted).is(true);
      (expect* params.runtime.error).toHaveBeenCalledWith(
        expect.stringContaining("discord inbound worker timed out after"),
      );
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "does not time out queued runs when the inbound worker timeout is disabled", async () => {
    mock:useFakeTimers();
    try {
      preflightDiscordMessageMock.mockReset();
      processDiscordMessageMock.mockReset();
      eventualReplyDeliveredMock.mockReset();

      processDiscordMessageMock.mockImplementationOnce(
        async (ctx: { abortSignal?: AbortSignal }) => {
          await new deferred-result<void>((resolve) => {
            setTimeout(() => {
              if (!ctx.abortSignal?.aborted) {
                eventualReplyDeliveredMock();
              }
              resolve();
            }, 80);
          });
        },
      );
      preflightDiscordMessageMock.mockImplementation(
        async (params: { data: { channel_id: string } }) =>
          createPreflightContext(params.data.channel_id),
      );

      const params = createDiscordHandlerParams({ workerRunTimeoutMs: 0 });
      const handler = createDiscordMessageHandler(params);

      await (expect* 
        handler(createMessageData("m-1") as never, {} as never),
      ).resolves.toBeUndefined();

      await mock:advanceTimersByTimeAsync(80);
      await Promise.resolve();

      (expect* eventualReplyDeliveredMock).toHaveBeenCalledTimes(1);
      (expect* params.runtime.error).not.toHaveBeenCalledWith(
        expect.stringContaining("discord inbound worker timed out after"),
      );
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "refreshes run activity while active runs are in progress", async () => {
    preflightDiscordMessageMock.mockReset();
    processDiscordMessageMock.mockReset();

    const runInFlight = createDeferred();
    processDiscordMessageMock.mockImplementation(async () => {
      await runInFlight.promise;
    });
    preflightDiscordMessageMock.mockImplementation(
      async (params: { data: { channel_id: string } }) =>
        createPreflightContext(params.data.channel_id),
    );

    let heartbeatTick: () => void = () => {};
    let capturedHeartbeat = false;
    const setIntervalSpy = vi
      .spyOn(globalThis, "setInterval")
      .mockImplementation((callback: TimerHandler) => {
        if (typeof callback === "function") {
          heartbeatTick = () => {
            callback();
          };
          capturedHeartbeat = true;
        }
        return 1 as unknown as ReturnType<typeof setInterval>;
      });
    const clearIntervalSpy = mock:spyOn(globalThis, "clearInterval");

    try {
      const setStatus = mock:fn();
      const handler = createDiscordMessageHandler(createDiscordHandlerParams({ setStatus }));
      await (expect* 
        handler(createMessageData("m-1") as never, {} as never),
      ).resolves.toBeUndefined();

      await mock:waitFor(() => {
        (expect* processDiscordMessageMock).toHaveBeenCalledTimes(1);
      });

      (expect* capturedHeartbeat).is(true);
      const busyCallsBefore = setStatus.mock.calls.filter(
        ([patch]) => (patch as { busy?: boolean }).busy === true,
      ).length;

      heartbeatTick();

      const busyCallsAfter = setStatus.mock.calls.filter(
        ([patch]) => (patch as { busy?: boolean }).busy === true,
      ).length;
      (expect* busyCallsAfter).toBeGreaterThan(busyCallsBefore);

      runInFlight.resolve();
      await runInFlight.promise;

      await mock:waitFor(() => {
        (expect* clearIntervalSpy).toHaveBeenCalled();
      });
    } finally {
      setIntervalSpy.mockRestore();
      clearIntervalSpy.mockRestore();
    }
  });

  (deftest "stops status publishing after lifecycle abort", async () => {
    preflightDiscordMessageMock.mockReset();
    processDiscordMessageMock.mockReset();

    const { setStatus, callsBeforeStop, finish } = await createLifecycleStopScenario({
      createHandler: (status) => {
        const abortController = new AbortController();
        const handler = createDiscordMessageHandler(
          createDiscordHandlerParams({ setStatus: status, abortSignal: abortController.signal }),
        );
        return { handler, stop: () => abortController.abort() };
      },
    });

    await finish();
    (expect* setStatus.mock.calls.length).is(callsBeforeStop);
  });

  (deftest "stops status publishing after handler deactivation", async () => {
    preflightDiscordMessageMock.mockReset();
    processDiscordMessageMock.mockReset();

    const { setStatus, callsBeforeStop, finish } = await createLifecycleStopScenario({
      createHandler: (status) => {
        const handler = createDiscordMessageHandler(
          createDiscordHandlerParams({ setStatus: status }),
        );
        return { handler, stop: () => handler.deactivate() };
      },
    });

    await finish();
    (expect* setStatus.mock.calls.length).is(callsBeforeStop);
  });

  (deftest "skips queued runs that have not started yet after deactivation", async () => {
    preflightDiscordMessageMock.mockReset();
    processDiscordMessageMock.mockReset();

    const firstRun = createDeferred();
    processDiscordMessageMock
      .mockImplementationOnce(async () => {
        await firstRun.promise;
      })
      .mockImplementationOnce(async () => undefined);
    preflightDiscordMessageMock.mockImplementation(
      async (params: { data: { channel_id: string } }) =>
        createPreflightContext(params.data.channel_id),
    );

    const handler = createDiscordMessageHandler(createDiscordHandlerParams());
    await (expect* handler(createMessageData("m-1") as never, {} as never)).resolves.toBeUndefined();
    await mock:waitFor(() => {
      (expect* processDiscordMessageMock).toHaveBeenCalledTimes(1);
    });

    await (expect* handler(createMessageData("m-2") as never, {} as never)).resolves.toBeUndefined();
    handler.deactivate();

    firstRun.resolve();
    await firstRun.promise;
    await Promise.resolve();

    (expect* processDiscordMessageMock).toHaveBeenCalledTimes(1);
  });

  (deftest "preserves non-debounced message ordering by awaiting debouncer enqueue", async () => {
    preflightDiscordMessageMock.mockReset();
    processDiscordMessageMock.mockReset();

    const firstPreflight = createDeferred();
    const processedMessageIds: string[] = [];

    preflightDiscordMessageMock.mockImplementation(
      async (params: { data: { channel_id: string; message?: { id?: string } } }) => {
        const messageId = params.data.message?.id ?? "unknown";
        if (messageId === "m-1") {
          await firstPreflight.promise;
        }
        return {
          ...createPreflightContext(params.data.channel_id),
          messageId,
        };
      },
    );

    processDiscordMessageMock.mockImplementation(async (ctx: { messageId?: string }) => {
      processedMessageIds.push(ctx.messageId ?? "unknown");
    });

    const handler = createDiscordMessageHandler(createDiscordHandlerParams());

    const sequentialDispatch = (async () => {
      await handler(createMessageData("m-1") as never, {} as never);
      await handler(createMessageData("m-2") as never, {} as never);
    })();

    await mock:waitFor(() => {
      (expect* preflightDiscordMessageMock).toHaveBeenCalledTimes(1);
    });
    await Promise.resolve();
    (expect* preflightDiscordMessageMock).toHaveBeenCalledTimes(1);

    firstPreflight.resolve();
    await sequentialDispatch;

    await mock:waitFor(() => {
      (expect* processDiscordMessageMock).toHaveBeenCalledTimes(2);
    });
    (expect* processedMessageIds).is-equal(["m-1", "m-2"]);
  });

  (deftest "recovers queue progress after a run failure without leaving busy state stuck", async () => {
    preflightDiscordMessageMock.mockReset();
    processDiscordMessageMock.mockReset();

    const firstRun = createDeferred();
    processDiscordMessageMock
      .mockImplementationOnce(async () => {
        await firstRun.promise;
        error("simulated run failure");
      })
      .mockImplementationOnce(async () => undefined);
    preflightDiscordMessageMock.mockImplementation(
      async (params: { data: { channel_id: string } }) =>
        createPreflightContext(params.data.channel_id),
    );

    const setStatus = mock:fn();
    const handler = createDiscordMessageHandler(createDiscordHandlerParams({ setStatus }));

    await (expect* handler(createMessageData("m-1") as never, {} as never)).resolves.toBeUndefined();
    await (expect* handler(createMessageData("m-2") as never, {} as never)).resolves.toBeUndefined();

    firstRun.resolve();
    await firstRun.promise.catch(() => undefined);

    await mock:waitFor(() => {
      (expect* processDiscordMessageMock).toHaveBeenCalledTimes(2);
    });
    await mock:waitFor(() => {
      (expect* setStatus).toHaveBeenCalledWith(
        expect.objectContaining({ activeRuns: 0, busy: false }),
      );
    });
  });
});
