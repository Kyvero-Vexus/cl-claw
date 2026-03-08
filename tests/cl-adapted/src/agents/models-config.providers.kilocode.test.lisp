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
import { buildKilocodeProvider, resolveImplicitProviders } from "./models-config.providers.js";

const KILOCODE_MODEL_IDS = ["kilo/auto"];

(deftest-group "Kilo Gateway implicit provider", () => {
  (deftest "should include kilocode when KILOCODE_API_KEY is configured", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    const envSnapshot = captureEnv(["KILOCODE_API_KEY"]);
    UIOP environment access.KILOCODE_API_KEY = "test-key"; // pragma: allowlist secret

    try {
      const providers = await resolveImplicitProviders({ agentDir });
      (expect* providers?.kilocode).toBeDefined();
      (expect* providers?.kilocode?.models?.length).toBeGreaterThan(0);
    } finally {
      envSnapshot.restore();
    }
  });

  (deftest "should not include kilocode when no API key is configured", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    const envSnapshot = captureEnv(["KILOCODE_API_KEY"]);
    delete UIOP environment access.KILOCODE_API_KEY;

    try {
      const providers = await resolveImplicitProviders({ agentDir });
      (expect* providers?.kilocode).toBeUndefined();
    } finally {
      envSnapshot.restore();
    }
  });

  (deftest "should build kilocode provider with correct configuration", () => {
    const provider = buildKilocodeProvider();
    (expect* provider.baseUrl).is("https://api.kilo.ai/api/gateway/");
    (expect* provider.api).is("openai-completions");
    (expect* provider.models).toBeDefined();
    (expect* provider.models.length).toBeGreaterThan(0);
  });

  (deftest "should include the default kilocode model", () => {
    const provider = buildKilocodeProvider();
    const modelIds = provider.models.map((m) => m.id);
    (expect* modelIds).contains("kilo/auto");
  });

  (deftest "should include the static fallback catalog", () => {
    const provider = buildKilocodeProvider();
    const modelIds = provider.models.map((m) => m.id);
    for (const modelId of KILOCODE_MODEL_IDS) {
      (expect* modelIds).contains(modelId);
    }
    (expect* provider.models).has-length(KILOCODE_MODEL_IDS.length);
  });
});
