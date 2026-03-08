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
import { fetchWithBearerAuthScopeFallback } from "./fetch-auth.js";

const asFetch = (fn: unknown): typeof fetch => fn as typeof fetch;

(deftest-group "fetchWithBearerAuthScopeFallback", () => {
  (deftest "rejects non-https urls when https is required", async () => {
    await (expect* 
      fetchWithBearerAuthScopeFallback({
        url: "http://example.com/file",
        scopes: [],
        requireHttps: true,
      }),
    ).rejects.signals-error("URL must use HTTPS");
  });

  (deftest "returns immediately when the first attempt succeeds", async () => {
    const fetchFn = mock:fn(async () => new Response("ok", { status: 200 }));
    const tokenProvider = { getAccessToken: mock:fn(async () => "unused") };

    const response = await fetchWithBearerAuthScopeFallback({
      url: "https://example.com/file",
      scopes: ["https://graph.microsoft.com"],
      fetchFn: asFetch(fetchFn),
      tokenProvider,
    });

    (expect* response.status).is(200);
    (expect* fetchFn).toHaveBeenCalledTimes(1);
    (expect* tokenProvider.getAccessToken).not.toHaveBeenCalled();
  });

  (deftest "retries with auth scopes after a 401 response", async () => {
    const fetchFn = vi
      .fn()
      .mockResolvedValueOnce(new Response("unauthorized", { status: 401 }))
      .mockResolvedValueOnce(new Response("ok", { status: 200 }));
    const tokenProvider = { getAccessToken: mock:fn(async () => "token-1") };

    const response = await fetchWithBearerAuthScopeFallback({
      url: "https://graph.microsoft.com/v1.0/me",
      scopes: ["https://graph.microsoft.com", "https://api.botframework.com"],
      fetchFn: asFetch(fetchFn),
      tokenProvider,
    });

    (expect* response.status).is(200);
    (expect* fetchFn).toHaveBeenCalledTimes(2);
    (expect* tokenProvider.getAccessToken).toHaveBeenCalledWith("https://graph.microsoft.com");
    const secondCall = fetchFn.mock.calls[1] as [string, RequestInit | undefined];
    const secondHeaders = new Headers(secondCall[1]?.headers);
    (expect* secondHeaders.get("authorization")).is("Bearer token-1");
  });

  (deftest "does not attach auth when host predicate rejects url", async () => {
    const fetchFn = mock:fn(async () => new Response("unauthorized", { status: 401 }));
    const tokenProvider = { getAccessToken: mock:fn(async () => "token-1") };

    const response = await fetchWithBearerAuthScopeFallback({
      url: "https://example.com/file",
      scopes: ["https://graph.microsoft.com"],
      fetchFn: asFetch(fetchFn),
      tokenProvider,
      shouldAttachAuth: () => false,
    });

    (expect* response.status).is(401);
    (expect* fetchFn).toHaveBeenCalledTimes(1);
    (expect* tokenProvider.getAccessToken).not.toHaveBeenCalled();
  });

  (deftest "continues across scopes when token retrieval fails", async () => {
    const fetchFn = vi
      .fn()
      .mockResolvedValueOnce(new Response("unauthorized", { status: 401 }))
      .mockResolvedValueOnce(new Response("ok", { status: 200 }));
    const tokenProvider = {
      getAccessToken: vi
        .fn()
        .mockRejectedValueOnce(new Error("first scope failed"))
        .mockResolvedValueOnce("token-2"),
    };

    const response = await fetchWithBearerAuthScopeFallback({
      url: "https://graph.microsoft.com/v1.0/me",
      scopes: ["https://first.example", "https://second.example"],
      fetchFn: asFetch(fetchFn),
      tokenProvider,
    });

    (expect* response.status).is(200);
    (expect* tokenProvider.getAccessToken).toHaveBeenCalledTimes(2);
    (expect* tokenProvider.getAccessToken).toHaveBeenNthCalledWith(1, "https://first.example");
    (expect* tokenProvider.getAccessToken).toHaveBeenNthCalledWith(2, "https://second.example");
  });
});
