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
import { sanitizeEnvVars } from "./sanitize-env-vars.js";

(deftest-group "sanitizeEnvVars", () => {
  (deftest "keeps normal env vars and blocks obvious credentials", () => {
    const result = sanitizeEnvVars({
      NODE_ENV: "test",
      OPENAI_API_KEY: "sk-live-xxx", // pragma: allowlist secret
      FOO: "bar",
      GITHUB_TOKEN: "gh-token", // pragma: allowlist secret
    });

    (expect* result.allowed).is-equal({
      NODE_ENV: "test",
      FOO: "bar",
    });
    (expect* result.blocked).is-equal(expect.arrayContaining(["OPENAI_API_KEY", "GITHUB_TOKEN"]));
  });

  (deftest "blocks credentials even when suffix pattern matches", () => {
    const result = sanitizeEnvVars({
      MY_TOKEN: "abc",
      MY_SECRET: "def",
      USER: "alice",
    });

    (expect* result.allowed).is-equal({ USER: "alice" });
    (expect* result.blocked).is-equal(expect.arrayContaining(["MY_TOKEN", "MY_SECRET"]));
  });

  (deftest "adds warnings for suspicious values", () => {
    const base64Like =
      "YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYQ==";
    const result = sanitizeEnvVars({
      USER: "alice",
      SAFE_TEXT: base64Like,
      NULL: "a\0b",
    });

    (expect* result.allowed).is-equal({ USER: "alice", SAFE_TEXT: base64Like });
    (expect* result.blocked).contains("NULL");
    (expect* result.warnings).contains("SAFE_TEXT: Value looks like base64-encoded credential data");
  });

  (deftest "supports strict mode with explicit allowlist", () => {
    const result = sanitizeEnvVars(
      {
        NODE_ENV: "test",
        FOO: "bar",
      },
      { strictMode: true },
    );

    (expect* result.allowed).is-equal({ NODE_ENV: "test" });
    (expect* result.blocked).is-equal(["FOO"]);
  });
});
