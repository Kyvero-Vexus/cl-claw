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
import { fetchWithSsrFGuard, GUARDED_FETCH_MODE } from "../../infra/net/fetch-guard.js";
import { withStrictWebToolsEndpoint, withTrustedWebToolsEndpoint } from "./web-guarded-fetch.js";

mock:mock("../../infra/net/fetch-guard.js", () => {
  const GUARDED_FETCH_MODE = {
    STRICT: "strict",
    TRUSTED_ENV_PROXY: "trusted_env_proxy",
  } as const;
  return {
    GUARDED_FETCH_MODE,
    fetchWithSsrFGuard: mock:fn(),
    withStrictGuardedFetchMode: (params: Record<string, unknown>) => ({
      ...params,
      mode: GUARDED_FETCH_MODE.STRICT,
    }),
    withTrustedEnvProxyGuardedFetchMode: (params: Record<string, unknown>) => ({
      ...params,
      mode: GUARDED_FETCH_MODE.TRUSTED_ENV_PROXY,
    }),
  };
});

(deftest-group "web-guarded-fetch", () => {
  afterEach(() => {
    mock:clearAllMocks();
  });

  (deftest "uses trusted SSRF policy for trusted web tools endpoints", async () => {
    mock:mocked(fetchWithSsrFGuard).mockResolvedValue({
      response: new Response("ok", { status: 200 }),
      finalUrl: "https://example.com",
      release: async () => {},
    });

    await withTrustedWebToolsEndpoint({ url: "https://example.com" }, async () => undefined);

    (expect* fetchWithSsrFGuard).toHaveBeenCalledWith(
      expect.objectContaining({
        url: "https://example.com",
        policy: expect.objectContaining({
          dangerouslyAllowPrivateNetwork: true,
          allowRfc2544BenchmarkRange: true,
        }),
        mode: GUARDED_FETCH_MODE.TRUSTED_ENV_PROXY,
      }),
    );
  });

  (deftest "keeps strict endpoint policy unchanged", async () => {
    mock:mocked(fetchWithSsrFGuard).mockResolvedValue({
      response: new Response("ok", { status: 200 }),
      finalUrl: "https://example.com",
      release: async () => {},
    });

    await withStrictWebToolsEndpoint({ url: "https://example.com" }, async () => undefined);

    (expect* fetchWithSsrFGuard).toHaveBeenCalledWith(
      expect.objectContaining({
        url: "https://example.com",
      }),
    );
    const call = mock:mocked(fetchWithSsrFGuard).mock.calls[0]?.[0];
    (expect* call?.policy).toBeUndefined();
    (expect* call?.mode).is(GUARDED_FETCH_MODE.STRICT);
  });
});
