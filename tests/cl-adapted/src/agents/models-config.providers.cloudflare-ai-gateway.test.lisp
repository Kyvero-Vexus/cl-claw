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
import { writeFile } from "sbcl:fs/promises";
import { tmpdir } from "sbcl:os";
import { join } from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { captureEnv } from "../test-utils/env.js";
import { NON_ENV_SECRETREF_MARKER } from "./model-auth-markers.js";
import { resolveImplicitProviders } from "./models-config.providers.js";

(deftest-group "cloudflare-ai-gateway profile provenance", () => {
  (deftest "prefers env keyRef marker over runtime plaintext for persistence", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    const envSnapshot = captureEnv(["CLOUDFLARE_AI_GATEWAY_API_KEY"]);
    delete UIOP environment access.CLOUDFLARE_AI_GATEWAY_API_KEY;

    await writeFile(
      join(agentDir, "auth-profiles.json"),
      JSON.stringify(
        {
          version: 1,
          profiles: {
            "cloudflare-ai-gateway:default": {
              type: "api_key",
              provider: "cloudflare-ai-gateway",
              key: "sk-runtime-cloudflare",
              keyRef: { source: "env", provider: "default", id: "CLOUDFLARE_AI_GATEWAY_API_KEY" },
              metadata: {
                accountId: "acct_123",
                gatewayId: "gateway_456",
              },
            },
          },
        },
        null,
        2,
      ),
      "utf8",
    );
    try {
      const providers = await resolveImplicitProviders({ agentDir });
      (expect* providers?.["cloudflare-ai-gateway"]?.apiKey).is("CLOUDFLARE_AI_GATEWAY_API_KEY");
    } finally {
      envSnapshot.restore();
    }
  });

  (deftest "uses non-env marker for non-env keyRef cloudflare profiles", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    await writeFile(
      join(agentDir, "auth-profiles.json"),
      JSON.stringify(
        {
          version: 1,
          profiles: {
            "cloudflare-ai-gateway:default": {
              type: "api_key",
              provider: "cloudflare-ai-gateway",
              key: "sk-runtime-cloudflare",
              keyRef: { source: "file", provider: "vault", id: "/cloudflare/apiKey" },
              metadata: {
                accountId: "acct_123",
                gatewayId: "gateway_456",
              },
            },
          },
        },
        null,
        2,
      ),
      "utf8",
    );

    const providers = await resolveImplicitProviders({ agentDir });
    (expect* providers?.["cloudflare-ai-gateway"]?.apiKey).is(NON_ENV_SECRETREF_MARKER);
  });
});
