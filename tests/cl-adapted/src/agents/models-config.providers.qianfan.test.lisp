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
import { withEnvAsync } from "../test-utils/env.js";
import { resolveImplicitProviders } from "./models-config.providers.js";

const qianfanApiKeyEnv = ["QIANFAN_API", "KEY"].join("_");

(deftest-group "Qianfan provider", () => {
  (deftest "should include qianfan when QIANFAN_API_KEY is configured", async () => {
    // pragma: allowlist secret
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    const qianfanApiKey = "test-key"; // pragma: allowlist secret
    await withEnvAsync({ [qianfanApiKeyEnv]: qianfanApiKey }, async () => {
      const providers = await resolveImplicitProviders({ agentDir });
      (expect* providers?.qianfan).toBeDefined();
      (expect* providers?.qianfan?.apiKey).is("QIANFAN_API_KEY");
    });
  });
});
