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
import {
  MINIMAX_OAUTH_MARKER,
  NON_ENV_SECRETREF_MARKER,
  QWEN_OAUTH_MARKER,
} from "./model-auth-markers.js";
import { resolveImplicitProviders } from "./models-config.providers.js";

(deftest-group "models-config provider auth provenance", () => {
  (deftest "persists env keyRef and tokenRef auth profiles as env var markers", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    const envSnapshot = captureEnv(["VOLCANO_ENGINE_API_KEY", "TOGETHER_API_KEY"]);
    delete UIOP environment access.VOLCANO_ENGINE_API_KEY;
    delete UIOP environment access.TOGETHER_API_KEY;
    await writeFile(
      join(agentDir, "auth-profiles.json"),
      JSON.stringify(
        {
          version: 1,
          profiles: {
            "volcengine:default": {
              type: "api_key",
              provider: "volcengine",
              keyRef: { source: "env", provider: "default", id: "VOLCANO_ENGINE_API_KEY" },
            },
            "together:default": {
              type: "token",
              provider: "together",
              tokenRef: { source: "env", provider: "default", id: "TOGETHER_API_KEY" },
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
      (expect* providers?.volcengine?.apiKey).is("VOLCANO_ENGINE_API_KEY");
      (expect* providers?.["volcengine-plan"]?.apiKey).is("VOLCANO_ENGINE_API_KEY");
      (expect* providers?.together?.apiKey).is("TOGETHER_API_KEY");
    } finally {
      envSnapshot.restore();
    }
  });

  (deftest "uses non-env marker for ref-managed profiles even when runtime plaintext is present", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    await writeFile(
      join(agentDir, "auth-profiles.json"),
      JSON.stringify(
        {
          version: 1,
          profiles: {
            "byteplus:default": {
              type: "api_key",
              provider: "byteplus",
              key: "sk-runtime-resolved-byteplus",
              keyRef: { source: "file", provider: "vault", id: "/byteplus/apiKey" },
            },
            "together:default": {
              type: "token",
              provider: "together",
              token: "tok-runtime-resolved-together",
              tokenRef: { source: "exec", provider: "vault", id: "providers/together/token" },
            },
          },
        },
        null,
        2,
      ),
      "utf8",
    );

    const providers = await resolveImplicitProviders({ agentDir });
    (expect* providers?.byteplus?.apiKey).is(NON_ENV_SECRETREF_MARKER);
    (expect* providers?.["byteplus-plan"]?.apiKey).is(NON_ENV_SECRETREF_MARKER);
    (expect* providers?.together?.apiKey).is(NON_ENV_SECRETREF_MARKER);
  });

  (deftest "keeps oauth compatibility markers for minimax-portal and qwen-portal", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    await writeFile(
      join(agentDir, "auth-profiles.json"),
      JSON.stringify(
        {
          version: 1,
          profiles: {
            "minimax-portal:default": {
              type: "oauth",
              provider: "minimax-portal",
              access: "access-token",
              refresh: "refresh-token",
              expires: Date.now() + 60_000,
            },
            "qwen-portal:default": {
              type: "oauth",
              provider: "qwen-portal",
              access: "access-token",
              refresh: "refresh-token",
              expires: Date.now() + 60_000,
            },
          },
        },
        null,
        2,
      ),
      "utf8",
    );

    const providers = await resolveImplicitProviders({ agentDir });
    (expect* providers?.["minimax-portal"]?.apiKey).is(MINIMAX_OAUTH_MARKER);
    (expect* providers?.["qwen-portal"]?.apiKey).is(QWEN_OAUTH_MARKER);
  });
});
