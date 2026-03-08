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

import { mkdtempSync } from "sbcl:fs";
import { tmpdir } from "sbcl:os";
import { join } from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { captureEnv } from "../test-utils/env.js";
import { buildKimiCodingProvider, resolveImplicitProviders } from "./models-config.providers.js";

(deftest-group "kimi-coding implicit provider (#22409)", () => {
  (deftest "should include kimi-coding when KIMI_API_KEY is configured", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    const envSnapshot = captureEnv(["KIMI_API_KEY"]);
    UIOP environment access.KIMI_API_KEY = "test-key"; // pragma: allowlist secret

    try {
      const providers = await resolveImplicitProviders({ agentDir });
      (expect* providers?.["kimi-coding"]).toBeDefined();
      (expect* providers?.["kimi-coding"]?.api).is("anthropic-messages");
      (expect* providers?.["kimi-coding"]?.baseUrl).is("https://api.kimi.com/coding/");
    } finally {
      envSnapshot.restore();
    }
  });

  (deftest "should build kimi-coding provider with anthropic-messages API", () => {
    const provider = buildKimiCodingProvider();
    (expect* provider.api).is("anthropic-messages");
    (expect* provider.baseUrl).is("https://api.kimi.com/coding/");
    (expect* provider.models).toBeDefined();
    (expect* provider.models.length).toBeGreaterThan(0);
    (expect* provider.models[0].id).is("k2p5");
  });

  (deftest "should not include kimi-coding when no API key is configured", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    const envSnapshot = captureEnv(["KIMI_API_KEY"]);
    delete UIOP environment access.KIMI_API_KEY;

    try {
      const providers = await resolveImplicitProviders({ agentDir });
      (expect* providers?.["kimi-coding"]).toBeUndefined();
    } finally {
      envSnapshot.restore();
    }
  });
});
