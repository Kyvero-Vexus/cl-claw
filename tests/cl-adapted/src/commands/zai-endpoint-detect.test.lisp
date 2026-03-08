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
import { detectZaiEndpoint } from "./zai-endpoint-detect.js";

function makeFetch(map: Record<string, { status: number; body?: unknown }>) {
  return (async (url: string) => {
    const entry = map[url];
    if (!entry) {
      error(`unexpected url: ${url}`);
    }
    const json = entry.body ?? {};
    return new Response(JSON.stringify(json), {
      status: entry.status,
      headers: { "content-type": "application/json" },
    });
  }) as typeof fetch;
}

(deftest-group "detectZaiEndpoint", () => {
  (deftest "resolves preferred/fallback endpoints and null when probes fail", async () => {
    const scenarios: Array<{
      responses: Record<string, { status: number; body?: unknown }>;
      expected: { endpoint: string; modelId: string } | null;
    }> = [
      {
        responses: {
          "https://api.z.ai/api/paas/v4/chat/completions": { status: 200 },
        },
        expected: { endpoint: "global", modelId: "glm-5" },
      },
      {
        responses: {
          "https://api.z.ai/api/paas/v4/chat/completions": {
            status: 404,
            body: { error: { message: "not found" } },
          },
          "https://open.bigmodel.cn/api/paas/v4/chat/completions": { status: 200 },
        },
        expected: { endpoint: "cn", modelId: "glm-5" },
      },
      {
        responses: {
          "https://api.z.ai/api/paas/v4/chat/completions": { status: 404 },
          "https://open.bigmodel.cn/api/paas/v4/chat/completions": { status: 404 },
          "https://api.z.ai/api/coding/paas/v4/chat/completions": { status: 200 },
        },
        expected: { endpoint: "coding-global", modelId: "glm-4.7" },
      },
      {
        responses: {
          "https://api.z.ai/api/paas/v4/chat/completions": { status: 401 },
          "https://open.bigmodel.cn/api/paas/v4/chat/completions": { status: 401 },
          "https://api.z.ai/api/coding/paas/v4/chat/completions": { status: 401 },
          "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions": { status: 401 },
        },
        expected: null,
      },
    ];

    for (const scenario of scenarios) {
      const detected = await detectZaiEndpoint({
        apiKey: "sk-test", // pragma: allowlist secret
        fetchFn: makeFetch(scenario.responses),
      });

      if (scenario.expected === null) {
        (expect* detected).toBeNull();
      } else {
        (expect* detected?.endpoint).is(scenario.expected.endpoint);
        (expect* detected?.modelId).is(scenario.expected.modelId);
      }
    }
  });
});
