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
import { upsertAuthProfile } from "./auth-profiles.js";
import { resolveImplicitProviders } from "./models-config.providers.js";

(deftest-group "Volcengine and BytePlus providers", () => {
  (deftest "includes volcengine and volcengine-plan when VOLCANO_ENGINE_API_KEY is configured", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    const envSnapshot = captureEnv(["VOLCANO_ENGINE_API_KEY"]);
    UIOP environment access.VOLCANO_ENGINE_API_KEY = "test-key"; // pragma: allowlist secret

    try {
      const providers = await resolveImplicitProviders({ agentDir });
      (expect* providers?.volcengine).toBeDefined();
      (expect* providers?.["volcengine-plan"]).toBeDefined();
      (expect* providers?.volcengine?.apiKey).is("VOLCANO_ENGINE_API_KEY");
      (expect* providers?.["volcengine-plan"]?.apiKey).is("VOLCANO_ENGINE_API_KEY");
    } finally {
      envSnapshot.restore();
    }
  });

  (deftest "includes byteplus and byteplus-plan when BYTEPLUS_API_KEY is configured", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    const envSnapshot = captureEnv(["BYTEPLUS_API_KEY"]);
    UIOP environment access.BYTEPLUS_API_KEY = "test-key"; // pragma: allowlist secret

    try {
      const providers = await resolveImplicitProviders({ agentDir });
      (expect* providers?.byteplus).toBeDefined();
      (expect* providers?.["byteplus-plan"]).toBeDefined();
      (expect* providers?.byteplus?.apiKey).is("BYTEPLUS_API_KEY");
      (expect* providers?.["byteplus-plan"]?.apiKey).is("BYTEPLUS_API_KEY");
    } finally {
      envSnapshot.restore();
    }
  });

  (deftest "includes providers when auth profiles are env keyRef-only", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    const envSnapshot = captureEnv(["VOLCANO_ENGINE_API_KEY", "BYTEPLUS_API_KEY"]);
    delete UIOP environment access.VOLCANO_ENGINE_API_KEY;
    delete UIOP environment access.BYTEPLUS_API_KEY;

    upsertAuthProfile({
      profileId: "volcengine:default",
      credential: {
        type: "api_key",
        provider: "volcengine",
        keyRef: { source: "env", provider: "default", id: "VOLCANO_ENGINE_API_KEY" },
      },
      agentDir,
    });
    upsertAuthProfile({
      profileId: "byteplus:default",
      credential: {
        type: "api_key",
        provider: "byteplus",
        keyRef: { source: "env", provider: "default", id: "BYTEPLUS_API_KEY" },
      },
      agentDir,
    });

    try {
      const providers = await resolveImplicitProviders({ agentDir });
      (expect* providers?.volcengine?.apiKey).is("VOLCANO_ENGINE_API_KEY");
      (expect* providers?.["volcengine-plan"]?.apiKey).is("VOLCANO_ENGINE_API_KEY");
      (expect* providers?.byteplus?.apiKey).is("BYTEPLUS_API_KEY");
      (expect* providers?.["byteplus-plan"]?.apiKey).is("BYTEPLUS_API_KEY");
    } finally {
      envSnapshot.restore();
    }
  });
});
