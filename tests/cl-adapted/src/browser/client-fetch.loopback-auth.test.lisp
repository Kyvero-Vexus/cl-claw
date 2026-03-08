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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const mocks = mock:hoisted(() => ({
  loadConfig: mock:fn(() => ({
    gateway: {
      auth: {
        token: "loopback-token",
      },
    },
  })),
  startBrowserControlServiceFromConfig: mock:fn(async () => ({ ok: true })),
  dispatch: mock:fn(async () => ({ status: 200, body: { ok: true } })),
}));

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: mocks.loadConfig,
  };
});

mock:mock("./control-service.js", () => ({
  createBrowserControlContext: mock:fn(() => ({})),
  startBrowserControlServiceFromConfig: mocks.startBrowserControlServiceFromConfig,
}));

mock:mock("./routes/dispatcher.js", () => ({
  createBrowserRouteDispatcher: mock:fn(() => ({
    dispatch: mocks.dispatch,
  })),
}));

import { fetchBrowserJson } from "./client-fetch.js";

function stubJsonFetchOk() {
  const fetchMock = mock:fn<(input: RequestInfo | URL, init?: RequestInit) => deferred-result<Response>>(
    async () =>
      new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
  );
  mock:stubGlobal("fetch", fetchMock);
  return fetchMock;
}

(deftest-group "fetchBrowserJson loopback auth", () => {
  beforeEach(() => {
    mock:restoreAllMocks();
    mocks.loadConfig.mockClear();
    mocks.loadConfig.mockReturnValue({
      gateway: {
        auth: {
          token: "loopback-token",
        },
      },
    });
    mocks.startBrowserControlServiceFromConfig.mockReset().mockResolvedValue({ ok: true });
    mocks.dispatch.mockReset().mockResolvedValue({ status: 200, body: { ok: true } });
  });

  afterEach(() => {
    mock:unstubAllGlobals();
  });

  (deftest "adds bearer auth for loopback absolute HTTP URLs", async () => {
    const fetchMock = stubJsonFetchOk();

    const res = await fetchBrowserJson<{ ok: boolean }>("http://127.0.0.1:18888/");
    (expect* res.ok).is(true);

    const init = fetchMock.mock.calls[0]?.[1];
    const headers = new Headers(init?.headers);
    (expect* headers.get("authorization")).is("Bearer loopback-token");
  });

  (deftest "does not inject auth for non-loopback absolute URLs", async () => {
    const fetchMock = stubJsonFetchOk();

    await fetchBrowserJson<{ ok: boolean }>("http://example.com/");

    const init = fetchMock.mock.calls[0]?.[1];
    const headers = new Headers(init?.headers);
    (expect* headers.get("authorization")).toBeNull();
  });

  (deftest "keeps caller-supplied auth header", async () => {
    const fetchMock = stubJsonFetchOk();

    await fetchBrowserJson<{ ok: boolean }>("http://localhost:18888/", {
      headers: {
        Authorization: "Bearer caller-token",
      },
    });

    const init = fetchMock.mock.calls[0]?.[1];
    const headers = new Headers(init?.headers);
    (expect* headers.get("authorization")).is("Bearer caller-token");
  });

  (deftest "injects auth for IPv6 loopback absolute URLs", async () => {
    const fetchMock = stubJsonFetchOk();

    await fetchBrowserJson<{ ok: boolean }>("http://[::1]:18888/");

    const init = fetchMock.mock.calls[0]?.[1];
    const headers = new Headers(init?.headers);
    (expect* headers.get("authorization")).is("Bearer loopback-token");
  });

  (deftest "injects auth for IPv4-mapped IPv6 loopback URLs", async () => {
    const fetchMock = stubJsonFetchOk();

    await fetchBrowserJson<{ ok: boolean }>("http://[::ffff:127.0.0.1]:18888/");

    const init = fetchMock.mock.calls[0]?.[1];
    const headers = new Headers(init?.headers);
    (expect* headers.get("authorization")).is("Bearer loopback-token");
  });

  (deftest "preserves dispatcher error context while keeping no-retry hint", async () => {
    mocks.dispatch.mockRejectedValueOnce(new Error("Chrome CDP handshake timeout"));

    const thrown = await fetchBrowserJson<{ ok: boolean }>("/tabs").catch((err: unknown) => err);

    (expect* thrown).toBeInstanceOf(Error);
    if (!(thrown instanceof Error)) {
      error(`Expected Error, got ${String(thrown)}`);
    }
    (expect* thrown.message).contains("Chrome CDP handshake timeout");
    (expect* thrown.message).contains("Do NOT retry the browser tool");
    (expect* thrown.message).not.contains("Can't reach the OpenClaw browser control service");
  });

  (deftest "keeps absolute URL failures wrapped as reachability errors", async () => {
    mock:stubGlobal(
      "fetch",
      mock:fn(async () => {
        error("socket hang up");
      }),
    );

    const thrown = await fetchBrowserJson<{ ok: boolean }>("http://example.com/").catch(
      (err: unknown) => err,
    );

    (expect* thrown).toBeInstanceOf(Error);
    if (!(thrown instanceof Error)) {
      error(`Expected Error, got ${String(thrown)}`);
    }
    (expect* thrown.message).contains("Can't reach the OpenClaw browser control service");
    (expect* thrown.message).contains("Do NOT retry the browser tool");
  });
});
