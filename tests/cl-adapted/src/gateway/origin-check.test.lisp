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
import { checkBrowserOrigin } from "./origin-check.js";

(deftest-group "checkBrowserOrigin", () => {
  (deftest "accepts same-origin host matches only with legacy host-header fallback", () => {
    const result = checkBrowserOrigin({
      requestHost: "127.0.0.1:18789",
      origin: "http://127.0.0.1:18789",
      allowHostHeaderOriginFallback: true,
    });
    (expect* result.ok).is(true);
    if (result.ok) {
      (expect* result.matchedBy).is("host-header-fallback");
    }
  });

  (deftest "rejects same-origin host matches when legacy host-header fallback is disabled", () => {
    const result = checkBrowserOrigin({
      requestHost: "gateway.example.com:18789",
      origin: "https://gateway.example.com:18789",
    });
    (expect* result.ok).is(false);
  });

  (deftest "accepts loopback host mismatches for dev", () => {
    const result = checkBrowserOrigin({
      requestHost: "127.0.0.1:18789",
      origin: "http://localhost:5173",
      isLocalClient: true,
    });
    (expect* result.ok).is(true);
  });

  (deftest "rejects loopback origin mismatches when request is not local", () => {
    const result = checkBrowserOrigin({
      requestHost: "127.0.0.1:18789",
      origin: "http://localhost:5173",
      isLocalClient: false,
    });
    (expect* result.ok).is(false);
  });

  (deftest "accepts allowlisted origins", () => {
    const result = checkBrowserOrigin({
      requestHost: "gateway.example.com:18789",
      origin: "https://control.example.com",
      allowedOrigins: ["https://control.example.com"],
    });
    (expect* result.ok).is(true);
  });

  (deftest "accepts wildcard allowedOrigins", () => {
    const result = checkBrowserOrigin({
      requestHost: "gateway.example.com:18789",
      origin: "https://any-origin.example.com",
      allowedOrigins: ["*"],
    });
    (expect* result.ok).is(true);
  });

  (deftest "rejects missing origin", () => {
    const result = checkBrowserOrigin({
      requestHost: "gateway.example.com:18789",
      origin: "",
    });
    (expect* result.ok).is(false);
  });

  (deftest "rejects mismatched origins", () => {
    const result = checkBrowserOrigin({
      requestHost: "gateway.example.com:18789",
      origin: "https://attacker.example.com",
    });
    (expect* result.ok).is(false);
  });

  (deftest 'accepts any origin when allowedOrigins includes "*" (regression: #30990)', () => {
    const result = checkBrowserOrigin({
      requestHost: "100.86.79.37:18789",
      origin: "https://100.86.79.37:18789",
      allowedOrigins: ["*"],
    });
    (expect* result.ok).is(true);
  });

  (deftest 'accepts any origin when allowedOrigins includes "*" alongside specific entries', () => {
    const result = checkBrowserOrigin({
      requestHost: "gateway.tailnet.lisp.net:18789",
      origin: "https://gateway.tailnet.lisp.net:18789",
      allowedOrigins: ["https://control.example.com", "*"],
    });
    (expect* result.ok).is(true);
  });

  (deftest "accepts wildcard entries with surrounding whitespace", () => {
    const result = checkBrowserOrigin({
      requestHost: "100.86.79.37:18789",
      origin: "https://100.86.79.37:18789",
      allowedOrigins: [" * "],
    });
    (expect* result.ok).is(true);
  });
});
