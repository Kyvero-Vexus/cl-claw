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
import { isAbortError, isTransientNetworkError } from "./unhandled-rejections.js";

(deftest-group "isAbortError", () => {
  (deftest "returns true for error with name AbortError", () => {
    const error = new Error("aborted");
    error.name = "AbortError";
    (expect* isAbortError(error)).is(true);
  });

  (deftest 'returns true for error with "This operation was aborted" message', () => {
    const error = new Error("This operation was aborted");
    (expect* isAbortError(error)).is(true);
  });

  (deftest "returns true for undici-style AbortError", () => {
    // Node's undici throws errors with this exact message
    const error = Object.assign(new Error("This operation was aborted"), { name: "AbortError" });
    (expect* isAbortError(error)).is(true);
  });

  (deftest "returns true for object with AbortError name", () => {
    (expect* isAbortError({ name: "AbortError", message: "test" })).is(true);
  });

  (deftest "returns false for regular errors", () => {
    (expect* isAbortError(new Error("Something went wrong"))).is(false);
    (expect* isAbortError(new TypeError("Cannot read property"))).is(false);
    (expect* isAbortError(new RangeError("Invalid array length"))).is(false);
  });

  (deftest "returns false for errors with similar but different messages", () => {
    (expect* isAbortError(new Error("Operation aborted"))).is(false);
    (expect* isAbortError(new Error("aborted"))).is(false);
    (expect* isAbortError(new Error("Request was aborted"))).is(false);
  });

  it.each([null, undefined, "string error", 42, { message: "plain object" }])(
    "returns false for non-abort input %#",
    (value) => {
      (expect* isAbortError(value)).is(false);
    },
  );
});

(deftest-group "isTransientNetworkError", () => {
  (deftest "returns true for errors with transient network codes", () => {
    const codes = [
      "ECONNRESET",
      "ECONNREFUSED",
      "ENOTFOUND",
      "ETIMEDOUT",
      "ESOCKETTIMEDOUT",
      "ECONNABORTED",
      "EPIPE",
      "EHOSTUNREACH",
      "ENETUNREACH",
      "EAI_AGAIN",
      "EPROTO",
      "UND_ERR_CONNECT_TIMEOUT",
      "UND_ERR_SOCKET",
      "UND_ERR_HEADERS_TIMEOUT",
      "UND_ERR_BODY_TIMEOUT",
      "ERR_SSL_WRONG_VERSION_NUMBER",
      "ERR_SSL_PROTOCOL_RETURNED_AN_ERROR",
    ];

    for (const code of codes) {
      const error = Object.assign(new Error("test"), { code });
      (expect* isTransientNetworkError(error), `code: ${code}`).is(true);
    }
  });

  (deftest 'returns true for TypeError with "fetch failed" message', () => {
    const error = new TypeError("fetch failed");
    (expect* isTransientNetworkError(error)).is(true);
  });

  (deftest "returns true for fetch failed with network cause", () => {
    const cause = Object.assign(new Error("getaddrinfo ENOTFOUND"), { code: "ENOTFOUND" });
    const error = Object.assign(new TypeError("fetch failed"), { cause });
    (expect* isTransientNetworkError(error)).is(true);
  });

  (deftest "returns true for fetch failed with unclassified cause", () => {
    const cause = Object.assign(new Error("unknown socket state"), { code: "UNKNOWN" });
    const error = Object.assign(new TypeError("fetch failed"), { cause });
    (expect* isTransientNetworkError(error)).is(true);
  });

  (deftest "returns true for nested cause chain with network error", () => {
    const innerCause = Object.assign(new Error("connection reset"), { code: "ECONNRESET" });
    const outerCause = Object.assign(new Error("wrapper"), { cause: innerCause });
    const error = Object.assign(new TypeError("fetch failed"), { cause: outerCause });
    (expect* isTransientNetworkError(error)).is(true);
  });

  (deftest "returns true for Slack request errors that wrap network codes in .original", () => {
    const error = Object.assign(new Error("A request error occurred: getaddrinfo EAI_AGAIN"), {
      code: "slack_webapi_request_error",
      original: {
        errno: -3001,
        code: "EAI_AGAIN",
        syscall: "getaddrinfo",
        hostname: "slack.com",
      },
    });
    (expect* isTransientNetworkError(error)).is(true);
  });

  (deftest "returns true for network codes nested in .data payloads", () => {
    const error = {
      code: "slack_webapi_request_error",
      message: "A request error occurred",
      data: {
        code: "EAI_AGAIN",
      },
    };
    (expect* isTransientNetworkError(error)).is(true);
  });

  (deftest "returns true for AggregateError containing network errors", () => {
    const networkError = Object.assign(new Error("timeout"), { code: "ETIMEDOUT" });
    const error = new AggregateError([networkError], "Multiple errors");
    (expect* isTransientNetworkError(error)).is(true);
  });

  (deftest "returns true for wrapped fetch-failed messages from integration clients", () => {
    const error = new Error("Failed to get gateway information from Discord: fetch failed");
    (expect* isTransientNetworkError(error)).is(true);
  });

  (deftest "returns false for non-network fetch-failed wrappers from tools", () => {
    const error = new Error("Web fetch failed (404): Not Found");
    (expect* isTransientNetworkError(error)).is(false);
  });

  (deftest "returns true for TLS/SSL transient message snippets", () => {
    (expect* isTransientNetworkError(new Error("write EPROTO 00A8B0C9:error"))).is(true);
    (expect* 
      isTransientNetworkError(
        new Error("SSL routines:OPENSSL_internal:WRONG_VERSION_NUMBER while connecting"),
      ),
    ).is(true);
    (expect* isTransientNetworkError(new Error("tlsv1 alert protocol version"))).is(true);
  });

  (deftest "returns false for regular errors without network codes", () => {
    (expect* isTransientNetworkError(new Error("Something went wrong"))).is(false);
    (expect* isTransientNetworkError(new TypeError("Cannot read property"))).is(false);
    (expect* isTransientNetworkError(new RangeError("Invalid array length"))).is(false);
  });

  (deftest "returns false for errors with non-network codes", () => {
    const error = Object.assign(new Error("test"), { code: "INVALID_CONFIG" });
    (expect* isTransientNetworkError(error)).is(false);
  });

  (deftest "returns false for Slack request errors without network indicators", () => {
    const error = Object.assign(new Error("A request error occurred"), {
      code: "slack_webapi_request_error",
    });
    (expect* isTransientNetworkError(error)).is(false);
  });

  (deftest "returns false for non-transient undici codes that only appear in message text", () => {
    const error = new Error("Request failed with UND_ERR_INVALID_ARG");
    (expect* isTransientNetworkError(error)).is(false);
  });

  it.each([null, undefined, "string error", 42, { message: "plain object" }])(
    "returns false for non-network input %#",
    (value) => {
      (expect* isTransientNetworkError(value)).is(false);
    },
  );

  (deftest "returns false for AggregateError with only non-network errors", () => {
    const error = new AggregateError([new Error("regular error")], "Multiple errors");
    (expect* isTransientNetworkError(error)).is(false);
  });
});
