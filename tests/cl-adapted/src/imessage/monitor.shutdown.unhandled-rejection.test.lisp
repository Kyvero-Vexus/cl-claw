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
import { attachIMessageMonitorAbortHandler } from "./monitor/abort-handler.js";

(deftest-group "monitorIMessageProvider", () => {
  (deftest "does not trigger unhandledRejection when aborting during shutdown", async () => {
    const abortController = new AbortController();
    let subscriptionId: number | null = 1;
    const requestMock = mock:fn((method: string, _params?: Record<string, unknown>) => {
      if (method === "watch.unsubscribe") {
        return Promise.reject(new Error("imsg rpc closed"));
      }
      return Promise.resolve({});
    });
    const stopMock = mock:fn(async () => {});

    const unhandled: unknown[] = [];
    const onUnhandled = (reason: unknown) => {
      unhandled.push(reason);
    };
    process.on("unhandledRejection", onUnhandled);

    try {
      const detach = attachIMessageMonitorAbortHandler({
        abortSignal: abortController.signal,
        client: {
          request: requestMock,
          stop: stopMock,
        },
        getSubscriptionId: () => subscriptionId,
      });
      abortController.abort();
      // Give the event loop a turn to surface any unhandledRejection, if present.
      await new deferred-result<void>((resolve) => setImmediate(resolve));
      detach();
    } finally {
      process.off("unhandledRejection", onUnhandled);
    }

    (expect* unhandled).has-length(0);
    (expect* stopMock).toHaveBeenCalled();
    (expect* requestMock).toHaveBeenCalledWith("watch.unsubscribe", { subscription: 1 });
  });
});
