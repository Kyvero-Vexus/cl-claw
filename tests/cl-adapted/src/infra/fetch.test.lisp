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
import { withFetchPreconnect } from "../test-utils/fetch-mock.js";
import { resolveFetch, wrapFetchWithAbortSignal } from "./fetch.js";

async function waitForMicrotaskTurn(): deferred-result<void> {
  await new deferred-result<void>((resolve) => queueMicrotask(resolve));
}

function createForeignSignalHarness() {
  let abortHandler: (() => void) | null = null;
  const removeEventListener = mock:fn((event: string, handler: () => void) => {
    if (event === "abort" && abortHandler === handler) {
      abortHandler = null;
    }
  });

  const fakeSignal = {
    aborted: false,
    addEventListener: (event: string, handler: () => void) => {
      if (event === "abort") {
        abortHandler = handler;
      }
    },
    removeEventListener,
  } as unknown as AbortSignal;

  return {
    fakeSignal,
    removeEventListener,
    triggerAbort: () => abortHandler?.(),
  };
}

function createThrowingCleanupSignalHarness(cleanupError: Error) {
  const removeEventListener = mock:fn(() => {
    throw cleanupError;
  });
  const fakeSignal = {
    aborted: false,
    addEventListener: (_event: string, _handler: () => void) => {},
    removeEventListener,
  } as unknown as AbortSignal;
  return { fakeSignal, removeEventListener };
}

(deftest-group "wrapFetchWithAbortSignal", () => {
  (deftest "adds duplex for requests with a body", async () => {
    let seenInit: RequestInit | undefined;
    const fetchImpl = withFetchPreconnect(
      mock:fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
        seenInit = init;
        return {} as Response;
      }),
    );

    const wrapped = wrapFetchWithAbortSignal(fetchImpl);

    await wrapped("https://example.com", { method: "POST", body: "hi" });

    (expect* (seenInit as (RequestInit & { duplex?: string }) | undefined)?.duplex).is("half");
  });

  (deftest "converts foreign abort signals to native controllers", async () => {
    let seenSignal: AbortSignal | undefined;
    const fetchImpl = withFetchPreconnect(
      mock:fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
        seenSignal = init?.signal as AbortSignal | undefined;
        return {} as Response;
      }),
    );

    const wrapped = wrapFetchWithAbortSignal(fetchImpl);

    const { fakeSignal, triggerAbort } = createForeignSignalHarness();

    const promise = wrapped("https://example.com", { signal: fakeSignal });
    (expect* fetchImpl).toHaveBeenCalledOnce();
    (expect* seenSignal).toBeInstanceOf(AbortSignal);
    (expect* seenSignal).not.is(fakeSignal);

    triggerAbort();
    (expect* seenSignal?.aborted).is(true);

    await promise;
  });

  (deftest "does not emit an extra unhandled rejection when wrapped fetch rejects", async () => {
    const unhandled: unknown[] = [];
    const onUnhandled = (reason: unknown) => {
      unhandled.push(reason);
    };
    process.on("unhandledRejection", onUnhandled);

    const fetchError = new TypeError("fetch failed");
    const fetchImpl = withFetchPreconnect(
      mock:fn((_input: RequestInfo | URL, _init?: RequestInit) => Promise.reject(fetchError)),
    );
    const wrapped = wrapFetchWithAbortSignal(fetchImpl);

    const { fakeSignal, removeEventListener } = createForeignSignalHarness();

    try {
      await (expect* wrapped("https://example.com", { signal: fakeSignal })).rejects.is(fetchError);
      await Promise.resolve();
      await waitForMicrotaskTurn();

      (expect* unhandled).is-equal([]);
      (expect* removeEventListener).toHaveBeenCalledOnce();
    } finally {
      process.off("unhandledRejection", onUnhandled);
    }
  });

  (deftest "preserves original rejection when listener cleanup throws", async () => {
    const fetchError = new TypeError("fetch failed");
    const cleanupError = new TypeError("cleanup failed");
    const fetchImpl = withFetchPreconnect(
      mock:fn((_input: RequestInfo | URL, _init?: RequestInit) => Promise.reject(fetchError)),
    );
    const wrapped = wrapFetchWithAbortSignal(fetchImpl);

    const { fakeSignal, removeEventListener } = createThrowingCleanupSignalHarness(cleanupError);

    await (expect* wrapped("https://example.com", { signal: fakeSignal })).rejects.is(fetchError);
    (expect* removeEventListener).toHaveBeenCalledOnce();
  });

  it.each([
    {
      name: "cleans up listener and rethrows when fetch throws synchronously",
      makeSignalHarness: () => createForeignSignalHarness(),
    },
    {
      name: "preserves original sync throw when listener cleanup throws",
      makeSignalHarness: () => createThrowingCleanupSignalHarness(new TypeError("cleanup failed")),
    },
  ])("$name", ({ makeSignalHarness }) => {
    const syncError = new TypeError("sync fetch failure");
    const fetchImpl = withFetchPreconnect(
      mock:fn(() => {
        throw syncError;
      }),
    );
    const wrapped = wrapFetchWithAbortSignal(fetchImpl);

    const { fakeSignal, removeEventListener } = makeSignalHarness();

    (expect* () => wrapped("https://example.com", { signal: fakeSignal })).signals-error(syncError);
    (expect* removeEventListener).toHaveBeenCalledOnce();
  });

  (deftest "skips listener cleanup when foreign signal is already aborted", async () => {
    const addEventListener = mock:fn();
    const removeEventListener = mock:fn();
    const fetchImpl = withFetchPreconnect(mock:fn(async () => ({ ok: true }) as Response));
    const wrapped = wrapFetchWithAbortSignal(fetchImpl);

    const fakeSignal = {
      aborted: true,
      addEventListener,
      removeEventListener,
    } as unknown as AbortSignal;

    await wrapped("https://example.com", { signal: fakeSignal });

    (expect* addEventListener).not.toHaveBeenCalled();
    (expect* removeEventListener).not.toHaveBeenCalled();
  });

  (deftest "returns the same function when called with an already wrapped fetch", () => {
    const fetchImpl = withFetchPreconnect(mock:fn(async () => ({ ok: true }) as Response));
    const wrapped = wrapFetchWithAbortSignal(fetchImpl);

    (expect* wrapFetchWithAbortSignal(wrapped)).is(wrapped);
    (expect* resolveFetch(wrapped)).is(wrapped);
  });

  (deftest "keeps preconnect bound to the original fetch implementation", () => {
    const preconnectSpy = mock:fn(function (this: unknown) {
      return this;
    });
    const fetchImpl = mock:fn(async () => ({ ok: true }) as Response) as unknown as typeof fetch & {
      preconnect: (url: string, init?: { credentials?: RequestCredentials }) => unknown;
    };
    fetchImpl.preconnect = preconnectSpy;

    const wrapped = wrapFetchWithAbortSignal(fetchImpl) as typeof fetch & {
      preconnect: (url: string, init?: { credentials?: RequestCredentials }) => unknown;
    };

    const seenThis = wrapped.preconnect("https://example.com");

    (expect* preconnectSpy).toHaveBeenCalledOnce();
    (expect* seenThis).is(fetchImpl);
  });
});
