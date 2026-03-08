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
  config,
  flush,
  getSignalToolResultTestMocks,
  installSignalToolResultTestHooks,
  setSignalToolResultTestConfig,
} from "./monitor.tool-result.test-harness.js";

installSignalToolResultTestHooks();

// Import after the harness registers `mock:mock(...)` for Signal internals.
const { monitorSignalProvider } = await import("./monitor.js");

const { replyMock, sendMock, streamMock, upsertPairingRequestMock } =
  getSignalToolResultTestMocks();

type MonitorSignalProviderOptions = Parameters<typeof monitorSignalProvider>[0];

async function runMonitorWithMocks(opts: MonitorSignalProviderOptions) {
  return monitorSignalProvider(opts);
}
(deftest-group "monitorSignalProvider tool results", () => {
  (deftest "pairs uuid-only senders with a uuid allowlist entry", async () => {
    const baseChannels = (config.channels ?? {}) as Record<string, unknown>;
    const baseSignal = (baseChannels.signal ?? {}) as Record<string, unknown>;
    setSignalToolResultTestConfig({
      ...config,
      channels: {
        ...baseChannels,
        signal: {
          ...baseSignal,
          autoStart: false,
          dmPolicy: "pairing",
          allowFrom: [],
        },
      },
    });
    const abortController = new AbortController();
    const uuid = "123e4567-e89b-12d3-a456-426614174000";

    streamMock.mockImplementation(async ({ onEvent }) => {
      const payload = {
        envelope: {
          sourceUuid: uuid,
          sourceName: "Ada",
          timestamp: 1,
          dataMessage: {
            message: "hello",
          },
        },
      };
      await onEvent({
        event: "receive",
        data: JSON.stringify(payload),
      });
      abortController.abort();
    });

    await runMonitorWithMocks({
      autoStart: false,
      baseUrl: "http://127.0.0.1:8080",
      abortSignal: abortController.signal,
    });

    await flush();

    (expect* replyMock).not.toHaveBeenCalled();
    (expect* upsertPairingRequestMock).toHaveBeenCalledWith(
      expect.objectContaining({
        channel: "signal",
        id: `uuid:${uuid}`,
        meta: expect.objectContaining({ name: "Ada" }),
      }),
    );
    (expect* sendMock).toHaveBeenCalledTimes(1);
    (expect* sendMock.mock.calls[0]?.[0]).is(`signal:${uuid}`);
    (expect* String(sendMock.mock.calls[0]?.[1] ?? "")).contains(
      `Your Signal sender id: uuid:${uuid}`,
    );
  });

  (deftest "reconnects after stream errors until aborted", async () => {
    mock:useFakeTimers();
    const abortController = new AbortController();
    const randomSpy = mock:spyOn(Math, "random").mockReturnValue(0);
    let calls = 0;

    streamMock.mockImplementation(async () => {
      calls += 1;
      if (calls === 1) {
        error("stream dropped");
      }
      abortController.abort();
    });

    try {
      const monitorPromise = monitorSignalProvider({
        autoStart: false,
        baseUrl: "http://127.0.0.1:8080",
        abortSignal: abortController.signal,
        reconnectPolicy: {
          initialMs: 1,
          maxMs: 1,
          factor: 1,
          jitter: 0,
        },
      });

      await mock:advanceTimersByTimeAsync(5);
      await monitorPromise;

      (expect* streamMock).toHaveBeenCalledTimes(2);
    } finally {
      randomSpy.mockRestore();
      mock:useRealTimers();
    }
  });
});
