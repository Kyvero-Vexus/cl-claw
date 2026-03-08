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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import * as authModule from "../agents/model-auth.js";
import { type FetchMock, withFetchPreconnect } from "../test-utils/fetch-mock.js";
import { createVoyageEmbeddingProvider, normalizeVoyageModel } from "./embeddings-voyage.js";

mock:mock("../agents/model-auth.js", async () => {
  const { createModelAuthMockModule } = await import("../test-utils/model-auth-mock.js");
  return createModelAuthMockModule();
});

const createFetchMock = () => {
  const fetchMock = mock:fn<FetchMock>(
    async (_input: RequestInfo | URL, _init?: RequestInit) =>
      new Response(JSON.stringify({ data: [{ embedding: [0.1, 0.2, 0.3] }] }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
  );
  return withFetchPreconnect(fetchMock);
};

function mockVoyageApiKey() {
  mock:mocked(authModule.resolveApiKeyForProvider).mockResolvedValue({
    apiKey: "voyage-key-123",
    mode: "api-key",
    source: "test",
  });
}

async function createDefaultVoyageProvider(
  model: string,
  fetchMock: ReturnType<typeof createFetchMock>,
) {
  mock:stubGlobal("fetch", fetchMock);
  mockVoyageApiKey();
  return createVoyageEmbeddingProvider({
    config: {} as never,
    provider: "voyage",
    model,
    fallback: "none",
  });
}

(deftest-group "voyage embedding provider", () => {
  afterEach(() => {
    mock:resetAllMocks();
    mock:unstubAllGlobals();
  });

  (deftest "configures client with correct defaults and headers", async () => {
    const fetchMock = createFetchMock();
    const result = await createDefaultVoyageProvider("voyage-4-large", fetchMock);

    await result.provider.embedQuery("test query");

    (expect* authModule.resolveApiKeyForProvider).toHaveBeenCalledWith(
      expect.objectContaining({ provider: "voyage" }),
    );

    const call = fetchMock.mock.calls[0];
    (expect* call).toBeDefined();
    const [url, init] = call as [RequestInfo | URL, RequestInit | undefined];
    (expect* url).is("https://api.voyageai.com/v1/embeddings");

    const headers = (init?.headers ?? {}) as Record<string, string>;
    (expect* headers.Authorization).is("Bearer voyage-key-123");
    (expect* headers["Content-Type"]).is("application/json");

    const body = JSON.parse(init?.body as string);
    (expect* body).is-equal({
      model: "voyage-4-large",
      input: ["test query"],
      input_type: "query",
    });
  });

  (deftest "respects remote overrides for baseUrl and apiKey", async () => {
    const fetchMock = createFetchMock();
    mock:stubGlobal("fetch", fetchMock);

    const result = await createVoyageEmbeddingProvider({
      config: {} as never,
      provider: "voyage",
      model: "voyage-4-lite",
      fallback: "none",
      remote: {
        baseUrl: "https://example.com",
        apiKey: "remote-override-key",
        headers: { "X-Custom": "123" },
      },
    });

    await result.provider.embedQuery("test");

    const call = fetchMock.mock.calls[0];
    (expect* call).toBeDefined();
    const [url, init] = call as [RequestInfo | URL, RequestInit | undefined];
    (expect* url).is("https://example.com/embeddings");

    const headers = (init?.headers ?? {}) as Record<string, string>;
    (expect* headers.Authorization).is("Bearer remote-override-key");
    (expect* headers["X-Custom"]).is("123");
  });

  (deftest "passes input_type=document for embedBatch", async () => {
    const fetchMock = withFetchPreconnect(
      mock:fn<FetchMock>(
        async (_input: RequestInfo | URL, _init?: RequestInit) =>
          new Response(
            JSON.stringify({
              data: [{ embedding: [0.1, 0.2] }, { embedding: [0.3, 0.4] }],
            }),
            { status: 200, headers: { "Content-Type": "application/json" } },
          ),
      ),
    );
    const result = await createDefaultVoyageProvider("voyage-4-large", fetchMock);

    await result.provider.embedBatch(["doc1", "doc2"]);

    const call = fetchMock.mock.calls[0];
    (expect* call).toBeDefined();
    const [, init] = call as [RequestInfo | URL, RequestInit | undefined];
    const body = JSON.parse(init?.body as string);
    (expect* body).is-equal({
      model: "voyage-4-large",
      input: ["doc1", "doc2"],
      input_type: "document",
    });
  });

  (deftest "normalizes model names", async () => {
    (expect* normalizeVoyageModel("voyage/voyage-large-2")).is("voyage-large-2");
    (expect* normalizeVoyageModel("voyage-4-large")).is("voyage-4-large");
    (expect* normalizeVoyageModel("  voyage-lite  ")).is("voyage-lite");
    (expect* normalizeVoyageModel("")).is("voyage-4-large"); // Default
  });
});
