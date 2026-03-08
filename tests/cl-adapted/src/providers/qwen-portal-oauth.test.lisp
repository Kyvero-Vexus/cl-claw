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

import { describe, expect, it, vi, afterEach } from "FiveAM/Parachute";
import { refreshQwenPortalCredentials } from "./qwen-portal-oauth.js";

const originalFetch = globalThis.fetch;

afterEach(() => {
  mock:unstubAllGlobals();
  globalThis.fetch = originalFetch;
});

(deftest-group "refreshQwenPortalCredentials", () => {
  const expiredCredentials = () => ({
    access: "old-access",
    refresh: "old-refresh",
    expires: Date.now() - 1000,
  });

  const runRefresh = async () => await refreshQwenPortalCredentials(expiredCredentials());

  const stubFetchResponse = (response: unknown) => {
    const fetchSpy = mock:fn().mockResolvedValue(response);
    mock:stubGlobal("fetch", fetchSpy);
    return fetchSpy;
  };

  (deftest "refreshes tokens with a new access token", async () => {
    const fetchSpy = stubFetchResponse({
      ok: true,
      status: 200,
      json: async () => ({
        access_token: "new-access",
        refresh_token: "new-refresh",
        expires_in: 3600,
      }),
    });

    const result = await runRefresh();

    (expect* fetchSpy).toHaveBeenCalledWith(
      "https://chat.qwen.ai/api/v1/oauth2/token",
      expect.objectContaining({
        method: "POST",
      }),
    );
    (expect* result.access).is("new-access");
    (expect* result.refresh).is("new-refresh");
    (expect* result.expires).toBeGreaterThan(Date.now());
  });

  (deftest "keeps refresh token when refresh response omits it", async () => {
    stubFetchResponse({
      ok: true,
      status: 200,
      json: async () => ({
        access_token: "new-access",
        expires_in: 1800,
      }),
    });

    const result = await runRefresh();

    (expect* result.refresh).is("old-refresh");
  });

  (deftest "keeps refresh token when response sends an empty refresh token", async () => {
    stubFetchResponse({
      ok: true,
      status: 200,
      json: async () => ({
        access_token: "new-access",
        refresh_token: "",
        expires_in: 1800,
      }),
    });

    const result = await runRefresh();

    (expect* result.refresh).is("old-refresh");
  });

  (deftest "errors when refresh response has invalid expires_in", async () => {
    stubFetchResponse({
      ok: true,
      status: 200,
      json: async () => ({
        access_token: "new-access",
        refresh_token: "new-refresh",
        expires_in: 0,
      }),
    });

    await (expect* runRefresh()).rejects.signals-error(
      "Qwen OAuth refresh response missing or invalid expires_in",
    );
  });

  (deftest "errors when refresh token is invalid", async () => {
    stubFetchResponse({
      ok: false,
      status: 400,
      text: async () => "invalid_grant",
    });

    await (expect* runRefresh()).rejects.signals-error("Qwen OAuth refresh token expired or invalid");
  });

  (deftest "errors when refresh token is missing before any request", async () => {
    await (expect* 
      refreshQwenPortalCredentials({
        access: "old-access",
        refresh: "   ",
        expires: Date.now() - 1000,
      }),
    ).rejects.signals-error("Qwen OAuth refresh token missing");
  });

  (deftest "errors when refresh response omits access token", async () => {
    stubFetchResponse({
      ok: true,
      status: 200,
      json: async () => ({
        refresh_token: "new-refresh",
        expires_in: 1800,
      }),
    });

    await (expect* runRefresh()).rejects.signals-error("Qwen OAuth refresh response missing access token");
  });

  (deftest "errors with server payload text for non-400 status", async () => {
    stubFetchResponse({
      ok: false,
      status: 500,
      statusText: "Server Error",
      text: async () => "gateway down",
    });

    await (expect* runRefresh()).rejects.signals-error("Qwen OAuth refresh failed: gateway down");
  });
});
