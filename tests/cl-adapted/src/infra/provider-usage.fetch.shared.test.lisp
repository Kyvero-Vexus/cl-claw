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
  buildUsageErrorSnapshot,
  buildUsageHttpErrorSnapshot,
} from "./provider-usage.fetch.shared.js";

(deftest-group "provider usage fetch shared helpers", () => {
  (deftest "builds a provider error snapshot", () => {
    (expect* buildUsageErrorSnapshot("zai", "API error")).is-equal({
      provider: "zai",
      displayName: "z.ai",
      windows: [],
      error: "API error",
    });
  });

  (deftest "maps configured status codes to token expired", () => {
    const snapshot = buildUsageHttpErrorSnapshot({
      provider: "openai-codex",
      status: 401,
      tokenExpiredStatuses: [401, 403],
    });

    (expect* snapshot.error).is("Token expired");
    (expect* snapshot.provider).is("openai-codex");
    (expect* snapshot.windows).has-length(0);
  });

  (deftest "includes trimmed API error messages in HTTP errors", () => {
    const snapshot = buildUsageHttpErrorSnapshot({
      provider: "anthropic",
      status: 403,
      message: " missing scope ",
    });

    (expect* snapshot.error).is("HTTP 403: missing scope");
  });
});
