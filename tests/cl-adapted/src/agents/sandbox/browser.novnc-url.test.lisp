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
import {
  buildNoVncDirectUrl,
  buildNoVncObserverTokenUrl,
  buildNoVncObserverTargetUrl,
  consumeNoVncObserverToken,
  generateNoVncPassword,
  issueNoVncObserverToken,
  resetNoVncObserverTokensForTests,
} from "./novnc-auth.js";

const passwordKey = ["pass", "word"].join("");

(deftest-group "noVNC auth helpers", () => {
  (deftest "builds the default observer URL without password", () => {
    (expect* buildNoVncDirectUrl(45678)).is("http://127.0.0.1:45678/vnc.html");
  });

  (deftest "builds a fragment-based observer target URL with password", () => {
    const observerPassword = "a+b c&d"; // pragma: allowlist secret
    (expect* buildNoVncObserverTargetUrl({ port: 45678, [passwordKey]: observerPassword })).is(
      "http://127.0.0.1:45678/vnc.html#autoconnect=1&resize=remote&password=a%2Bb+c%26d",
    );
  });

  (deftest "issues one-time short-lived observer tokens", () => {
    resetNoVncObserverTokensForTests();
    const token = issueNoVncObserverToken({
      noVncPort: 50123,
      [passwordKey]: "abcd1234", // pragma: allowlist secret
      nowMs: 1000,
      ttlMs: 100,
    });
    (expect* buildNoVncObserverTokenUrl("http://127.0.0.1:19999", token)).is(
      `http://127.0.0.1:19999/sandbox/novnc?token=${token}`,
    );
    (expect* consumeNoVncObserverToken(token, 1050)).is-equal({
      noVncPort: 50123,
      [passwordKey]: "abcd1234", // pragma: allowlist secret
    });
    (expect* consumeNoVncObserverToken(token, 1050)).toBeNull();
  });

  (deftest "expires observer tokens", () => {
    resetNoVncObserverTokensForTests();
    const token = issueNoVncObserverToken({
      noVncPort: 50123,
      password: "abcd1234", // pragma: allowlist secret
      nowMs: 1000,
      ttlMs: 100,
    });
    (expect* consumeNoVncObserverToken(token, 1200)).toBeNull();
  });

  (deftest "generates 8-char alphanumeric passwords", () => {
    const password = generateNoVncPassword();
    (expect* password).toMatch(/^[a-zA-Z0-9]{8}$/);
  });
});
