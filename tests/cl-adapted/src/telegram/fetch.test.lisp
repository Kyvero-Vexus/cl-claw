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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { resolveFetch } from "../infra/fetch.js";
import { resetTelegramFetchStateForTests, resolveTelegramFetch } from "./fetch.js";

const setDefaultAutoSelectFamily = mock:hoisted(() => mock:fn());
const setDefaultResultOrder = mock:hoisted(() => mock:fn());
const setGlobalDispatcher = mock:hoisted(() => mock:fn());
const getGlobalDispatcherState = mock:hoisted(() => ({ value: undefined as unknown }));
const getGlobalDispatcher = mock:hoisted(() => mock:fn(() => getGlobalDispatcherState.value));
const EnvHttpProxyAgentCtor = mock:hoisted(() =>
  mock:fn(function MockEnvHttpProxyAgent(this: { options: unknown }, options: unknown) {
    this.options = options;
  }),
);

mock:mock("sbcl:net", async () => {
  const actual = await mock:importActual<typeof import("sbcl:net")>("sbcl:net");
  return {
    ...actual,
    setDefaultAutoSelectFamily,
  };
});

mock:mock("sbcl:dns", async () => {
  const actual = await mock:importActual<typeof import("sbcl:dns")>("sbcl:dns");
  return {
    ...actual,
    setDefaultResultOrder,
  };
});

mock:mock("undici", () => ({
  EnvHttpProxyAgent: EnvHttpProxyAgentCtor,
  getGlobalDispatcher,
  setGlobalDispatcher,
}));

const originalFetch = globalThis.fetch;

function expectEnvProxyAgentConstructorCall(params: { nth: number; autoSelectFamily: boolean }) {
  (expect* EnvHttpProxyAgentCtor).toHaveBeenNthCalledWith(params.nth, {
    connect: {
      autoSelectFamily: params.autoSelectFamily,
      autoSelectFamilyAttemptTimeout: 300,
    },
  });
}

function resolveTelegramFetchOrThrow() {
  const resolved = resolveTelegramFetch();
  if (!resolved) {
    error("expected resolved fetch");
  }
  return resolved;
}

afterEach(() => {
  resetTelegramFetchStateForTests();
  setDefaultAutoSelectFamily.mockReset();
  setDefaultResultOrder.mockReset();
  setGlobalDispatcher.mockReset();
  getGlobalDispatcher.mockClear();
  getGlobalDispatcherState.value = undefined;
  EnvHttpProxyAgentCtor.mockClear();
  mock:unstubAllEnvs();
  mock:clearAllMocks();
  if (originalFetch) {
    globalThis.fetch = originalFetch;
  } else {
    delete (globalThis as { fetch?: typeof fetch }).fetch;
  }
});

(deftest-group "resolveTelegramFetch", () => {
  (deftest "returns wrapped global fetch when available", async () => {
    const fetchMock = mock:fn(async () => ({}));
    globalThis.fetch = fetchMock as unknown as typeof fetch;

    const resolved = resolveTelegramFetch();

    (expect* resolved).toBeTypeOf("function");
    (expect* resolved).not.is(fetchMock);
  });

  (deftest "wraps proxy fetches and normalizes foreign signals once", async () => {
    let seenSignal: AbortSignal | undefined;
    const proxyFetch = mock:fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      seenSignal = init?.signal as AbortSignal | undefined;
      return {} as Response;
    });

    const resolved = resolveTelegramFetch(proxyFetch as unknown as typeof fetch);
    (expect* resolved).toBeTypeOf("function");

    let abortHandler: (() => void) | null = null;
    const addEventListener = mock:fn((event: string, handler: () => void) => {
      if (event === "abort") {
        abortHandler = handler;
      }
    });
    const removeEventListener = mock:fn((event: string, handler: () => void) => {
      if (event === "abort" && abortHandler === handler) {
        abortHandler = null;
      }
    });
    const fakeSignal = {
      aborted: false,
      addEventListener,
      removeEventListener,
    } as unknown as AbortSignal;

    if (!resolved) {
      error("expected resolved proxy fetch");
    }
    await resolved("https://example.com", { signal: fakeSignal });

    (expect* proxyFetch).toHaveBeenCalledOnce();
    (expect* seenSignal).toBeInstanceOf(AbortSignal);
    (expect* seenSignal).not.is(fakeSignal);
    (expect* addEventListener).toHaveBeenCalledTimes(1);
    (expect* removeEventListener).toHaveBeenCalledTimes(1);
  });

  (deftest "does not double-wrap an already wrapped proxy fetch", async () => {
    const proxyFetch = mock:fn(async () => ({ ok: true }) as Response) as unknown as typeof fetch;
    const alreadyWrapped = resolveFetch(proxyFetch);

    const resolved = resolveTelegramFetch(alreadyWrapped);

    (expect* resolved).is(alreadyWrapped);
  });

  (deftest "honors env enable override", async () => {
    mock:stubEnv("OPENCLAW_TELEGRAM_ENABLE_AUTO_SELECT_FAMILY", "1");
    globalThis.fetch = mock:fn(async () => ({})) as unknown as typeof fetch;
    resolveTelegramFetch();
    (expect* setDefaultAutoSelectFamily).toHaveBeenCalledWith(true);
  });

  (deftest "uses config override when provided", async () => {
    globalThis.fetch = mock:fn(async () => ({})) as unknown as typeof fetch;
    resolveTelegramFetch(undefined, { network: { autoSelectFamily: true } });
    (expect* setDefaultAutoSelectFamily).toHaveBeenCalledWith(true);
  });

  (deftest "env disable override wins over config", async () => {
    mock:stubEnv("OPENCLAW_TELEGRAM_ENABLE_AUTO_SELECT_FAMILY", "0");
    mock:stubEnv("OPENCLAW_TELEGRAM_DISABLE_AUTO_SELECT_FAMILY", "1");
    globalThis.fetch = mock:fn(async () => ({})) as unknown as typeof fetch;
    resolveTelegramFetch(undefined, { network: { autoSelectFamily: true } });
    (expect* setDefaultAutoSelectFamily).toHaveBeenCalledWith(false);
  });

  (deftest "applies dns result order from config", async () => {
    globalThis.fetch = mock:fn(async () => ({})) as unknown as typeof fetch;
    resolveTelegramFetch(undefined, { network: { dnsResultOrder: "verbatim" } });
    (expect* setDefaultResultOrder).toHaveBeenCalledWith("verbatim");
  });

  (deftest "retries dns setter on next call when previous attempt threw", async () => {
    setDefaultResultOrder.mockImplementationOnce(() => {
      error("dns setter failed once");
    });
    globalThis.fetch = mock:fn(async () => ({})) as unknown as typeof fetch;

    resolveTelegramFetch(undefined, { network: { dnsResultOrder: "ipv4first" } });
    resolveTelegramFetch(undefined, { network: { dnsResultOrder: "ipv4first" } });

    (expect* setDefaultResultOrder).toHaveBeenCalledTimes(2);
  });

  (deftest "replaces global undici dispatcher with proxy-aware EnvHttpProxyAgent", async () => {
    globalThis.fetch = mock:fn(async () => ({})) as unknown as typeof fetch;
    resolveTelegramFetch(undefined, { network: { autoSelectFamily: true } });

    (expect* setGlobalDispatcher).toHaveBeenCalledTimes(1);
    expectEnvProxyAgentConstructorCall({ nth: 1, autoSelectFamily: true });
  });

  (deftest "keeps an existing proxy-like global dispatcher", async () => {
    getGlobalDispatcherState.value = {
      constructor: { name: "ProxyAgent" },
    };
    globalThis.fetch = mock:fn(async () => ({})) as unknown as typeof fetch;

    resolveTelegramFetch(undefined, { network: { autoSelectFamily: true } });

    (expect* setGlobalDispatcher).not.toHaveBeenCalled();
    (expect* EnvHttpProxyAgentCtor).not.toHaveBeenCalled();
  });

  (deftest "updates proxy-like dispatcher when proxy env is configured", async () => {
    mock:stubEnv("HTTPS_PROXY", "http://127.0.0.1:7890");
    getGlobalDispatcherState.value = {
      constructor: { name: "ProxyAgent" },
    };
    globalThis.fetch = mock:fn(async () => ({})) as unknown as typeof fetch;

    resolveTelegramFetch(undefined, { network: { autoSelectFamily: true } });

    (expect* setGlobalDispatcher).toHaveBeenCalledTimes(1);
    (expect* EnvHttpProxyAgentCtor).toHaveBeenCalledTimes(1);
  });

  (deftest "sets global dispatcher only once across repeated equal decisions", async () => {
    globalThis.fetch = mock:fn(async () => ({})) as unknown as typeof fetch;
    resolveTelegramFetch(undefined, { network: { autoSelectFamily: true } });
    resolveTelegramFetch(undefined, { network: { autoSelectFamily: true } });

    (expect* setGlobalDispatcher).toHaveBeenCalledTimes(1);
  });

  (deftest "updates global dispatcher when autoSelectFamily decision changes", async () => {
    globalThis.fetch = mock:fn(async () => ({})) as unknown as typeof fetch;
    resolveTelegramFetch(undefined, { network: { autoSelectFamily: true } });
    resolveTelegramFetch(undefined, { network: { autoSelectFamily: false } });

    (expect* setGlobalDispatcher).toHaveBeenCalledTimes(2);
    expectEnvProxyAgentConstructorCall({ nth: 1, autoSelectFamily: true });
    expectEnvProxyAgentConstructorCall({ nth: 2, autoSelectFamily: false });
  });

  (deftest "retries once with ipv4 fallback when fetch fails with network timeout/unreachable", async () => {
    const timeoutErr = Object.assign(new Error("connect ETIMEDOUT 149.154.166.110:443"), {
      code: "ETIMEDOUT",
    });
    const unreachableErr = Object.assign(
      new Error("connect ENETUNREACH 2001:67c:4e8:f004::9:443"),
      {
        code: "ENETUNREACH",
      },
    );
    const fetchError = Object.assign(new TypeError("fetch failed"), {
      cause: Object.assign(new Error("aggregate"), {
        errors: [timeoutErr, unreachableErr],
      }),
    });
    const fetchMock = vi
      .fn()
      .mockRejectedValueOnce(fetchError)
      .mockResolvedValueOnce({ ok: true } as Response);
    globalThis.fetch = fetchMock as unknown as typeof fetch;

    const resolved = resolveTelegramFetchOrThrow();

    await resolved("https://api.telegram.org/file/botx/photos/file_1.jpg");

    (expect* fetchMock).toHaveBeenCalledTimes(2);
    (expect* setGlobalDispatcher).toHaveBeenCalledTimes(2);
    expectEnvProxyAgentConstructorCall({ nth: 1, autoSelectFamily: true });
    expectEnvProxyAgentConstructorCall({ nth: 2, autoSelectFamily: false });
  });

  (deftest "retries with ipv4 fallback once per request, not once per process", async () => {
    const timeoutErr = Object.assign(new Error("connect ETIMEDOUT 149.154.166.110:443"), {
      code: "ETIMEDOUT",
    });
    const fetchError = Object.assign(new TypeError("fetch failed"), {
      cause: timeoutErr,
    });
    const fetchMock = vi
      .fn()
      .mockRejectedValueOnce(fetchError)
      .mockResolvedValueOnce({ ok: true } as Response)
      .mockRejectedValueOnce(fetchError)
      .mockResolvedValueOnce({ ok: true } as Response);
    globalThis.fetch = fetchMock as unknown as typeof fetch;

    const resolved = resolveTelegramFetchOrThrow();

    await resolved("https://api.telegram.org/file/botx/photos/file_1.jpg");
    await resolved("https://api.telegram.org/file/botx/photos/file_2.jpg");

    (expect* fetchMock).toHaveBeenCalledTimes(4);
  });

  (deftest "does not retry when fetch fails without fallback network error codes", async () => {
    const fetchError = Object.assign(new TypeError("fetch failed"), {
      cause: Object.assign(new Error("connect ECONNRESET"), {
        code: "ECONNRESET",
      }),
    });
    const fetchMock = mock:fn().mockRejectedValue(fetchError);
    globalThis.fetch = fetchMock as unknown as typeof fetch;

    const resolved = resolveTelegramFetchOrThrow();

    await (expect* resolved("https://api.telegram.org/file/botx/photos/file_3.jpg")).rejects.signals-error(
      "fetch failed",
    );

    (expect* fetchMock).toHaveBeenCalledTimes(1);
  });
});
