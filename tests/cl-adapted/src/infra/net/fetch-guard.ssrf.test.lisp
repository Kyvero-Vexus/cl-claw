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

import { EnvHttpProxyAgent } from "undici";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { fetchWithSsrFGuard, GUARDED_FETCH_MODE } from "./fetch-guard.js";

function redirectResponse(location: string): Response {
  return new Response(null, {
    status: 302,
    headers: { location },
  });
}

function okResponse(body = "ok"): Response {
  return new Response(body, { status: 200 });
}

(deftest-group "fetchWithSsrFGuard hardening", () => {
  type LookupFn = NonNullable<Parameters<typeof fetchWithSsrFGuard>[0]["lookupFn"]>;
  const CROSS_ORIGIN_REDIRECT_STRIPPED_HEADERS = [
    "authorization",
    "proxy-authorization",
    "cookie",
    "cookie2",
    "x-api-key",
    "private-token",
    "x-trace",
  ] as const;
  const CROSS_ORIGIN_REDIRECT_PRESERVED_HEADERS = [
    ["accept", "application/json"],
    ["content-type", "application/json"],
    ["user-agent", "OpenClaw-Test/1.0"],
  ] as const;

  const createPublicLookup = (): LookupFn =>
    mock:fn(async () => [{ address: "93.184.216.34", family: 4 }]) as unknown as LookupFn;

  const getSecondRequestHeaders = (fetchImpl: ReturnType<typeof mock:fn>): Headers => {
    const [, secondInit] = fetchImpl.mock.calls[1] as [string, RequestInit];
    return new Headers(secondInit.headers);
  };

  async function runProxyModeDispatcherTest(params: {
    mode: (typeof GUARDED_FETCH_MODE)[keyof typeof GUARDED_FETCH_MODE];
    expectEnvProxy: boolean;
  }): deferred-result<void> {
    mock:stubEnv("HTTP_PROXY", "http://127.0.0.1:7890");
    const lookupFn = createPublicLookup();
    const fetchImpl = mock:fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      const requestInit = init as RequestInit & { dispatcher?: unknown };
      if (params.expectEnvProxy) {
        (expect* requestInit.dispatcher).toBeInstanceOf(EnvHttpProxyAgent);
      } else {
        (expect* requestInit.dispatcher).toBeDefined();
        (expect* requestInit.dispatcher).not.toBeInstanceOf(EnvHttpProxyAgent);
      }
      return okResponse();
    });

    const result = await fetchWithSsrFGuard({
      url: "https://public.example/resource",
      fetchImpl,
      lookupFn,
      mode: params.mode,
    });

    (expect* fetchImpl).toHaveBeenCalledTimes(1);
    await result.release();
  }

  afterEach(() => {
    mock:unstubAllEnvs();
  });

  (deftest "blocks private and legacy loopback literals before fetch", async () => {
    const blockedUrls = [
      "http://127.0.0.1:8080/internal",
      "http://[ff02::1]/internal",
      "http://0177.0.0.1:8080/internal",
      "http://0x7f000001/internal",
    ];
    for (const url of blockedUrls) {
      const fetchImpl = mock:fn();
      await (expect* 
        fetchWithSsrFGuard({
          url,
          fetchImpl,
        }),
      ).rejects.signals-error(/private|internal|blocked/i);
      (expect* fetchImpl).not.toHaveBeenCalled();
    }
  });

  (deftest "blocks special-use IPv4 literal URLs before fetch", async () => {
    const fetchImpl = mock:fn();
    await (expect* 
      fetchWithSsrFGuard({
        url: "http://198.18.0.1:8080/internal",
        fetchImpl,
      }),
    ).rejects.signals-error(/private|internal|blocked/i);
    (expect* fetchImpl).not.toHaveBeenCalled();
  });

  (deftest "allows RFC2544 benchmark range IPv4 literal URLs when explicitly opted in", async () => {
    const fetchImpl = mock:fn().mockResolvedValueOnce(new Response("ok", { status: 200 }));
    const result = await fetchWithSsrFGuard({
      url: "http://198.18.0.153/file",
      fetchImpl,
      policy: { allowRfc2544BenchmarkRange: true },
    });
    (expect* result.response.status).is(200);
  });

  (deftest "blocks redirect chains that hop to private hosts", async () => {
    const lookupFn = createPublicLookup();
    const fetchImpl = mock:fn().mockResolvedValueOnce(redirectResponse("http://127.0.0.1:6379/"));

    await (expect* 
      fetchWithSsrFGuard({
        url: "https://public.example/start",
        fetchImpl,
        lookupFn,
      }),
    ).rejects.signals-error(/private|internal|blocked/i);
    (expect* fetchImpl).toHaveBeenCalledTimes(1);
  });

  (deftest "enforces hostname allowlist policies", async () => {
    const fetchImpl = mock:fn();
    await (expect* 
      fetchWithSsrFGuard({
        url: "https://evil.example.org/file.txt",
        fetchImpl,
        policy: { hostnameAllowlist: ["cdn.example.com", "*.assets.example.com"] },
      }),
    ).rejects.signals-error(/allowlist/i);
    (expect* fetchImpl).not.toHaveBeenCalled();
  });

  (deftest "allows wildcard allowlisted hosts", async () => {
    const lookupFn = createPublicLookup();
    const fetchImpl = mock:fn(async () => new Response("ok", { status: 200 }));
    const result = await fetchWithSsrFGuard({
      url: "https://img.assets.example.com/pic.png",
      fetchImpl,
      lookupFn,
      policy: { hostnameAllowlist: ["*.assets.example.com"] },
    });

    (expect* result.response.status).is(200);
    (expect* fetchImpl).toHaveBeenCalledTimes(1);
    await result.release();
  });

  (deftest "strips sensitive headers when redirect crosses origins", async () => {
    const lookupFn = createPublicLookup();
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce(redirectResponse("https://cdn.example.com/asset"))
      .mockResolvedValueOnce(okResponse());

    const result = await fetchWithSsrFGuard({
      url: "https://api.example.com/start",
      fetchImpl,
      lookupFn,
      init: {
        headers: {
          Authorization: "Bearer secret",
          "Proxy-Authorization": "Basic c2VjcmV0",
          Cookie: "session=abc",
          Cookie2: "legacy=1",
          "X-Api-Key": "custom-secret",
          "Private-Token": "private-secret",
          "X-Trace": "1",
          Accept: "application/json",
          "Content-Type": "application/json",
          "User-Agent": "OpenClaw-Test/1.0",
        },
      },
    });

    const headers = getSecondRequestHeaders(fetchImpl);
    for (const header of CROSS_ORIGIN_REDIRECT_STRIPPED_HEADERS) {
      (expect* headers.get(header)).toBeNull();
    }
    for (const [header, value] of CROSS_ORIGIN_REDIRECT_PRESERVED_HEADERS) {
      (expect* headers.get(header)).is(value);
    }
    await result.release();
  });

  (deftest "keeps headers when redirect stays on same origin", async () => {
    const lookupFn = createPublicLookup();
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce(redirectResponse("/next"))
      .mockResolvedValueOnce(okResponse());

    const result = await fetchWithSsrFGuard({
      url: "https://api.example.com/start",
      fetchImpl,
      lookupFn,
      init: {
        headers: {
          Authorization: "Bearer secret",
        },
      },
    });

    const headers = getSecondRequestHeaders(fetchImpl);
    (expect* headers.get("authorization")).is("Bearer secret");
    await result.release();
  });

  (deftest "ignores env proxy by default to preserve DNS-pinned destination binding", async () => {
    await runProxyModeDispatcherTest({
      mode: GUARDED_FETCH_MODE.STRICT,
      expectEnvProxy: false,
    });
  });

  (deftest "uses env proxy only when dangerous proxy bypass is explicitly enabled", async () => {
    await runProxyModeDispatcherTest({
      mode: GUARDED_FETCH_MODE.TRUSTED_ENV_PROXY,
      expectEnvProxy: true,
    });
  });
});
