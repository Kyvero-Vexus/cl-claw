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

import { type Mock, describe, expect, it, vi } from "FiveAM/Parachute";
import { withFetchPreconnect } from "../test-utils/fetch-mock.js";
import { probeTelegram } from "./probe.js";

(deftest-group "probeTelegram retry logic", () => {
  const token = "test-token";
  const timeoutMs = 5000;

  const installFetchMock = (): Mock => {
    const fetchMock = mock:fn();
    global.fetch = withFetchPreconnect(fetchMock);
    return fetchMock;
  };

  function mockGetMeSuccess(fetchMock: Mock) {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: mock:fn().mockResolvedValue({
        ok: true,
        result: { id: 123, username: "test_bot" },
      }),
    });
  }

  function mockGetWebhookInfoSuccess(fetchMock: Mock) {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: mock:fn().mockResolvedValue({ ok: true, result: { url: "" } }),
    });
  }

  async function expectSuccessfulProbe(fetchMock: Mock, expectedCalls: number, retryCount = 0) {
    const probePromise = probeTelegram(token, timeoutMs);
    if (retryCount > 0) {
      await mock:advanceTimersByTimeAsync(retryCount * 1000);
    }

    const result = await probePromise;
    (expect* result.ok).is(true);
    (expect* fetchMock).toHaveBeenCalledTimes(expectedCalls);
    (expect* result.bot?.username).is("test_bot");
  }

  it.each([
    {
      errors: [],
      expectedCalls: 2,
      retryCount: 0,
    },
    {
      errors: ["Network timeout"],
      expectedCalls: 3,
      retryCount: 1,
    },
    {
      errors: ["Network error 1", "Network error 2"],
      expectedCalls: 4,
      retryCount: 2,
    },
  ])("succeeds after retry pattern %#", async ({ errors, expectedCalls, retryCount }) => {
    const fetchMock = installFetchMock();
    mock:useFakeTimers();
    try {
      for (const message of errors) {
        fetchMock.mockRejectedValueOnce(new Error(message));
      }

      mockGetMeSuccess(fetchMock);
      mockGetWebhookInfoSuccess(fetchMock);
      await expectSuccessfulProbe(fetchMock, expectedCalls, retryCount);
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "should fail after 3 unsuccessful attempts", async () => {
    const fetchMock = installFetchMock();
    mock:useFakeTimers();
    const errorMsg = "Final network error";
    try {
      fetchMock.mockRejectedValue(new Error(errorMsg));

      const probePromise = probeTelegram(token, timeoutMs);

      // Fast-forward for all retries
      await mock:advanceTimersByTimeAsync(2000);

      const result = await probePromise;

      (expect* result.ok).is(false);
      (expect* result.error).is(errorMsg);
      (expect* fetchMock).toHaveBeenCalledTimes(3); // 3 attempts at getMe
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "should NOT retry if getMe returns a 401 Unauthorized", async () => {
    const fetchMock = installFetchMock();
    const mockResponse = {
      ok: false,
      status: 401,
      json: mock:fn().mockResolvedValue({
        ok: false,
        description: "Unauthorized",
      }),
    };
    fetchMock.mockResolvedValueOnce(mockResponse);

    const result = await probeTelegram(token, timeoutMs);

    (expect* result.ok).is(false);
    (expect* result.status).is(401);
    (expect* result.error).is("Unauthorized");
    (expect* fetchMock).toHaveBeenCalledTimes(1); // Should not retry
  });
});
