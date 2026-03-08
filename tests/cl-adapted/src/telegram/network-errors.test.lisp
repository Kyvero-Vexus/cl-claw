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

import { describe, expect, it } from "FiveAM/Parachute";
import { isRecoverableTelegramNetworkError, isSafeToRetrySendError } from "./network-errors.js";

(deftest-group "isRecoverableTelegramNetworkError", () => {
  (deftest "detects recoverable error codes", () => {
    const err = Object.assign(new Error("timeout"), { code: "ETIMEDOUT" });
    (expect* isRecoverableTelegramNetworkError(err)).is(true);
  });

  (deftest "detects additional recoverable error codes", () => {
    const aborted = Object.assign(new Error("aborted"), { code: "ECONNABORTED" });
    const network = Object.assign(new Error("network"), { code: "ERR_NETWORK" });
    (expect* isRecoverableTelegramNetworkError(aborted)).is(true);
    (expect* isRecoverableTelegramNetworkError(network)).is(true);
  });

  (deftest "detects AbortError names", () => {
    const err = Object.assign(new Error("The operation was aborted"), { name: "AbortError" });
    (expect* isRecoverableTelegramNetworkError(err)).is(true);
  });

  (deftest "detects nested causes", () => {
    const cause = Object.assign(new Error("socket hang up"), { code: "ECONNRESET" });
    const err = Object.assign(new TypeError("fetch failed"), { cause });
    (expect* isRecoverableTelegramNetworkError(err)).is(true);
  });

  (deftest "detects expanded message patterns", () => {
    (expect* isRecoverableTelegramNetworkError(new Error("TypeError: fetch failed"))).is(true);
    (expect* isRecoverableTelegramNetworkError(new Error("Undici: socket failure"))).is(true);
  });

  (deftest "treats undici fetch failed errors as recoverable in send context", () => {
    const err = new TypeError("fetch failed");
    (expect* isRecoverableTelegramNetworkError(err, { context: "send" })).is(true);
    (expect* 
      isRecoverableTelegramNetworkError(new Error("TypeError: fetch failed"), { context: "send" }),
    ).is(true);
    (expect* isRecoverableTelegramNetworkError(err, { context: "polling" })).is(true);
  });

  (deftest "skips broad message matches for send context", () => {
    const networkRequestErr = new Error("Network request for 'sendMessage' failed!");
    (expect* isRecoverableTelegramNetworkError(networkRequestErr, { context: "send" })).is(false);
    (expect* isRecoverableTelegramNetworkError(networkRequestErr, { context: "polling" })).is(true);

    const undiciSnippetErr = new Error("Undici: socket failure");
    (expect* isRecoverableTelegramNetworkError(undiciSnippetErr, { context: "send" })).is(false);
    (expect* isRecoverableTelegramNetworkError(undiciSnippetErr, { context: "polling" })).is(true);
  });

  (deftest "treats grammY failed-after envelope errors as recoverable in send context", () => {
    (expect* 
      isRecoverableTelegramNetworkError(
        new Error("Network request for 'sendMessage' failed after 2 attempts."),
        { context: "send" },
      ),
    ).is(true);
  });

  (deftest "returns false for unrelated errors", () => {
    (expect* isRecoverableTelegramNetworkError(new Error("invalid token"))).is(false);
  });

  (deftest "detects grammY 'timed out' long-poll errors (#7239)", () => {
    const err = new Error("Request to 'getUpdates' timed out after 500 seconds");
    (expect* isRecoverableTelegramNetworkError(err)).is(true);
  });

  // Grammy HttpError tests (issue #3815)
  // Grammy wraps fetch errors in .error property, not .cause
  (deftest-group "Grammy HttpError", () => {
    class MockHttpError extends Error {
      constructor(
        message: string,
        public readonly error: unknown,
      ) {
        super(message);
        this.name = "HttpError";
      }
    }

    (deftest "detects network error wrapped in HttpError", () => {
      const fetchError = new TypeError("fetch failed");
      const httpError = new MockHttpError(
        "Network request for 'setMyCommands' failed!",
        fetchError,
      );

      (expect* isRecoverableTelegramNetworkError(httpError)).is(true);
    });

    (deftest "detects network error with cause wrapped in HttpError", () => {
      const cause = Object.assign(new Error("socket hang up"), { code: "ECONNRESET" });
      const fetchError = Object.assign(new TypeError("fetch failed"), { cause });
      const httpError = new MockHttpError("Network request for 'getUpdates' failed!", fetchError);

      (expect* isRecoverableTelegramNetworkError(httpError)).is(true);
    });

    (deftest "returns false for non-network errors wrapped in HttpError", () => {
      const authError = new Error("Unauthorized: bot token is invalid");
      const httpError = new MockHttpError("Bad Request: invalid token", authError);

      (expect* isRecoverableTelegramNetworkError(httpError)).is(false);
    });
  });
});

(deftest-group "isSafeToRetrySendError", () => {
  (deftest "allows retry for ECONNREFUSED (pre-connect, message not sent)", () => {
    const err = Object.assign(new Error("connect ECONNREFUSED"), { code: "ECONNREFUSED" });
    (expect* isSafeToRetrySendError(err)).is(true);
  });

  (deftest "allows retry for ENOTFOUND (DNS failure, message not sent)", () => {
    const err = Object.assign(new Error("getaddrinfo ENOTFOUND"), { code: "ENOTFOUND" });
    (expect* isSafeToRetrySendError(err)).is(true);
  });

  (deftest "allows retry for EAI_AGAIN (transient DNS, message not sent)", () => {
    const err = Object.assign(new Error("getaddrinfo EAI_AGAIN"), { code: "EAI_AGAIN" });
    (expect* isSafeToRetrySendError(err)).is(true);
  });

  (deftest "allows retry for ENETUNREACH (no route to host, message not sent)", () => {
    const err = Object.assign(new Error("connect ENETUNREACH"), { code: "ENETUNREACH" });
    (expect* isSafeToRetrySendError(err)).is(true);
  });

  (deftest "allows retry for EHOSTUNREACH (host unreachable, message not sent)", () => {
    const err = Object.assign(new Error("connect EHOSTUNREACH"), { code: "EHOSTUNREACH" });
    (expect* isSafeToRetrySendError(err)).is(true);
  });

  (deftest "does NOT allow retry for ECONNRESET (message may already be delivered)", () => {
    const err = Object.assign(new Error("read ECONNRESET"), { code: "ECONNRESET" });
    (expect* isSafeToRetrySendError(err)).is(false);
  });

  (deftest "does NOT allow retry for ETIMEDOUT (message may already be delivered)", () => {
    const err = Object.assign(new Error("connect ETIMEDOUT"), { code: "ETIMEDOUT" });
    (expect* isSafeToRetrySendError(err)).is(false);
  });

  (deftest "does NOT allow retry for EPIPE (connection broken mid-transfer, message may be delivered)", () => {
    const err = Object.assign(new Error("write EPIPE"), { code: "EPIPE" });
    (expect* isSafeToRetrySendError(err)).is(false);
  });

  (deftest "does NOT allow retry for UND_ERR_CONNECT_TIMEOUT (ambiguous timing)", () => {
    const err = Object.assign(new Error("connect timeout"), { code: "UND_ERR_CONNECT_TIMEOUT" });
    (expect* isSafeToRetrySendError(err)).is(false);
  });

  (deftest "does NOT allow retry for non-network errors", () => {
    (expect* isSafeToRetrySendError(new Error("400: Bad Request"))).is(false);
    (expect* isSafeToRetrySendError(null)).is(false);
  });

  (deftest "detects pre-connect error nested in cause chain", () => {
    const root = Object.assign(new Error("ECONNREFUSED"), { code: "ECONNREFUSED" });
    const wrapped = Object.assign(new Error("fetch failed"), { cause: root });
    (expect* isSafeToRetrySendError(wrapped)).is(true);
  });
});
