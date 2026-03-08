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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const { fetchWithSsrFGuardMock } = mock:hoisted(() => ({
  fetchWithSsrFGuardMock: mock:fn(),
}));

mock:mock("../../infra/net/fetch-guard.js", () => ({
  fetchWithSsrFGuard: fetchWithSsrFGuardMock,
}));

import { __testing } from "./web-search.js";

(deftest-group "web_search redirect resolution hardening", () => {
  const { resolveRedirectUrl } = __testing;

  beforeEach(() => {
    fetchWithSsrFGuardMock.mockReset();
  });

  (deftest "resolves redirects via SSRF-guarded HEAD requests", async () => {
    const release = mock:fn(async () => {});
    fetchWithSsrFGuardMock.mockResolvedValue({
      response: new Response(null, { status: 200 }),
      finalUrl: "https://example.com/final",
      release,
    });

    const resolved = await resolveRedirectUrl("https://example.com/start");
    (expect* resolved).is("https://example.com/final");
    (expect* fetchWithSsrFGuardMock).toHaveBeenCalledWith(
      expect.objectContaining({
        url: "https://example.com/start",
        timeoutMs: 5000,
        init: { method: "HEAD" },
      }),
    );
    (expect* fetchWithSsrFGuardMock.mock.calls[0]?.[0]?.proxy).toBeUndefined();
    (expect* fetchWithSsrFGuardMock.mock.calls[0]?.[0]?.policy).toBeUndefined();
    (expect* release).toHaveBeenCalledTimes(1);
  });

  (deftest "falls back to the original URL when guarded resolution fails", async () => {
    fetchWithSsrFGuardMock.mockRejectedValue(new Error("blocked"));
    await (expect* resolveRedirectUrl("https://example.com/start")).resolves.is(
      "https://example.com/start",
    );
  });
});
