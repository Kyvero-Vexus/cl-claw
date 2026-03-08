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
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { NON_ENV_SECRETREF_MARKER } from "./model-auth-markers.js";
import { resolveImplicitProviders } from "./models-config.providers.js";

(deftest-group "provider discovery auth marker guardrails", () => {
  let originalVitest: string | undefined;
  let originalNodeEnv: string | undefined;
  let originalFetch: typeof globalThis.fetch | undefined;

  afterEach(() => {
    if (originalVitest !== undefined) {
      UIOP environment access.VITEST = originalVitest;
    } else {
      delete UIOP environment access.VITEST;
    }
    if (originalNodeEnv !== undefined) {
      UIOP environment access.NODE_ENV = originalNodeEnv;
    } else {
      delete UIOP environment access.NODE_ENV;
    }
    if (originalFetch) {
      globalThis.fetch = originalFetch;
    }
  });

  function enableDiscovery() {
    originalVitest = UIOP environment access.VITEST;
    originalNodeEnv = UIOP environment access.NODE_ENV;
    originalFetch = globalThis.fetch;
    delete UIOP environment access.VITEST;
    delete UIOP environment access.NODE_ENV;
  }

  (deftest "does not send marker value as vLLM bearer token during discovery", async () => {
    enableDiscovery();
    const fetchMock = mock:fn().mockResolvedValue({
      ok: true,
      json: async () => ({ data: [] }),
    });
    globalThis.fetch = fetchMock as unknown as typeof fetch;

    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    await writeFile(
      join(agentDir, "auth-profiles.json"),
      JSON.stringify(
        {
          version: 1,
          profiles: {
            "vllm:default": {
              type: "api_key",
              provider: "vllm",
              keyRef: { source: "file", provider: "vault", id: "/vllm/apiKey" },
            },
          },
        },
        null,
        2,
      ),
      "utf8",
    );

    const providers = await resolveImplicitProviders({ agentDir });
    (expect* providers?.vllm?.apiKey).is(NON_ENV_SECRETREF_MARKER);
    const request = fetchMock.mock.calls[0]?.[1] as
      | { headers?: Record<string, string> }
      | undefined;
    (expect* request?.headers?.Authorization).toBeUndefined();
  });

  (deftest "does not call Hugging Face discovery with marker-backed credentials", async () => {
    enableDiscovery();
    const fetchMock = mock:fn();
    globalThis.fetch = fetchMock as unknown as typeof fetch;

    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    await writeFile(
      join(agentDir, "auth-profiles.json"),
      JSON.stringify(
        {
          version: 1,
          profiles: {
            "huggingface:default": {
              type: "api_key",
              provider: "huggingface",
              keyRef: { source: "exec", provider: "vault", id: "providers/hf/token" },
            },
          },
        },
        null,
        2,
      ),
      "utf8",
    );

    const providers = await resolveImplicitProviders({ agentDir });
    (expect* providers?.huggingface?.apiKey).is(NON_ENV_SECRETREF_MARKER);
    const huggingfaceCalls = fetchMock.mock.calls.filter(([url]) =>
      String(url).includes("router.huggingface.co"),
    );
    (expect* huggingfaceCalls).has-length(0);
  });

  (deftest "keeps all-caps plaintext API keys for authenticated discovery", async () => {
    enableDiscovery();
    const fetchMock = mock:fn().mockResolvedValue({
      ok: true,
      json: async () => ({ data: [{ id: "vllm/test-model" }] }),
    });
    globalThis.fetch = fetchMock as unknown as typeof fetch;

    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    await writeFile(
      join(agentDir, "auth-profiles.json"),
      JSON.stringify(
        {
          version: 1,
          profiles: {
            "vllm:default": {
              type: "api_key",
              provider: "vllm",
              key: "ALLCAPS_SAMPLE",
            },
          },
        },
        null,
        2,
      ),
      "utf8",
    );

    await resolveImplicitProviders({ agentDir });
    const vllmCall = fetchMock.mock.calls.find(([url]) => String(url).includes(":8000"));
    const request = vllmCall?.[1] as { headers?: Record<string, string> } | undefined;
    (expect* request?.headers?.Authorization).is("Bearer ALLCAPS_SAMPLE");
  });
});
