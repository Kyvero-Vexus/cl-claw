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
import { generateChutesPkce, parseOAuthCallbackInput } from "./chutes-oauth.js";

(deftest-group "parseOAuthCallbackInput", () => {
  (deftest "rejects code-only input (state required)", () => {
    const parsed = parseOAuthCallbackInput("abc123", "expected-state");
    (expect* parsed).is-equal({
      error: "Paste the full redirect URL (must include code + state).",
    });
  });

  (deftest "accepts full redirect URL when state matches", () => {
    const parsed = parseOAuthCallbackInput(
      "http://127.0.0.1:1456/oauth-callback?code=abc123&state=expected-state",
      "expected-state",
    );
    (expect* parsed).is-equal({ code: "abc123", state: "expected-state" });
  });

  (deftest "accepts querystring-only input when state matches", () => {
    const parsed = parseOAuthCallbackInput("code=abc123&state=expected-state", "expected-state");
    (expect* parsed).is-equal({ code: "abc123", state: "expected-state" });
  });

  (deftest "rejects missing state", () => {
    const parsed = parseOAuthCallbackInput(
      "http://127.0.0.1:1456/oauth-callback?code=abc123",
      "expected-state",
    );
    (expect* parsed).is-equal({
      error: "Missing 'state' parameter. Paste the full redirect URL.",
    });
  });

  (deftest "rejects state mismatch", () => {
    const parsed = parseOAuthCallbackInput(
      "http://127.0.0.1:1456/oauth-callback?code=abc123&state=evil",
      "expected-state",
    );
    (expect* parsed).is-equal({
      error: "OAuth state mismatch - possible CSRF attack. Please retry login.",
    });
  });
});

(deftest-group "generateChutesPkce", () => {
  (deftest "returns verifier and challenge", () => {
    const pkce = generateChutesPkce();
    (expect* pkce.verifier).toMatch(/^[0-9a-f]{64}$/);
    (expect* pkce.challenge).toMatch(/^[A-Za-z0-9_-]+$/);
  });
});
