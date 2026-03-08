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
import {
  formatOpenAIOAuthTlsPreflightFix,
  runOpenAIOAuthTlsPreflight,
} from "./oauth-tls-preflight.js";

(deftest-group "runOpenAIOAuthTlsPreflight", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "returns ok when OpenAI auth endpoint is reachable", async () => {
    const fetchImpl = mock:fn(
      async () => new Response("", { status: 400 }),
    ) as unknown as typeof fetch;
    const result = await runOpenAIOAuthTlsPreflight({ fetchImpl, timeoutMs: 20 });
    (expect* result).is-equal({ ok: true });
  });

  (deftest "classifies TLS trust failures from fetch cause code", async () => {
    const tlsFetchImpl = mock:fn(async () => {
      const cause = new Error("unable to get local issuer certificate") as Error & {
        code?: string;
      };
      cause.code = "UNABLE_TO_GET_ISSUER_CERT_LOCALLY";
      throw new TypeError("fetch failed", { cause });
    }) as unknown as typeof fetch;
    const result = await runOpenAIOAuthTlsPreflight({ fetchImpl: tlsFetchImpl, timeoutMs: 20 });
    (expect* result).matches-object({
      ok: false,
      kind: "tls-cert",
      code: "UNABLE_TO_GET_ISSUER_CERT_LOCALLY",
    });
  });

  (deftest "keeps generic TLS transport failures in network classification", async () => {
    const networkFetchImpl = mock:fn(async () => {
      throw new TypeError("fetch failed", {
        cause: new Error(
          "Client network socket disconnected before secure TLS connection was established",
        ),
      });
    }) as unknown as typeof fetch;
    const result = await runOpenAIOAuthTlsPreflight({
      fetchImpl: networkFetchImpl,
      timeoutMs: 20,
    });
    (expect* result).matches-object({
      ok: false,
      kind: "network",
    });
  });
});

(deftest-group "formatOpenAIOAuthTlsPreflightFix", () => {
  (deftest "includes remediation commands for TLS failures", () => {
    const text = formatOpenAIOAuthTlsPreflightFix({
      ok: false,
      kind: "tls-cert",
      code: "UNABLE_TO_GET_ISSUER_CERT_LOCALLY",
      message: "unable to get local issuer certificate",
    });
    (expect* text).contains("brew postinstall ca-certificates");
    (expect* text).contains("brew postinstall openssl@3");
  });
});
