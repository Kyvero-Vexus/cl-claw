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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import * as ssrf from "../../infra/net/ssrf.js";
import { type FetchMock, withFetchPreconnect } from "../../test-utils/fetch-mock.js";

const lookupMock = mock:fn();
const resolvePinnedHostname = ssrf.resolvePinnedHostname;

function makeHeaders(map: Record<string, string>): { get: (key: string) => string | null } {
  return {
    get: (key) => map[key.toLowerCase()] ?? null,
  };
}

function redirectResponse(location: string): Response {
  return {
    ok: false,
    status: 302,
    headers: makeHeaders({ location }),
    body: { cancel: mock:fn() },
  } as unknown as Response;
}

function textResponse(body: string): Response {
  return {
    ok: true,
    status: 200,
    headers: makeHeaders({ "content-type": "text/plain" }),
    text: async () => body,
  } as unknown as Response;
}

function setMockFetch(
  impl: FetchMock = async (_input: RequestInfo | URL, _init?: RequestInit) => textResponse(""),
) {
  const fetchSpy = mock:fn<FetchMock>(impl);
  global.fetch = withFetchPreconnect(fetchSpy);
  return fetchSpy;
}

async function createWebFetchToolForTest(params?: {
  firecrawl?: { enabled?: boolean; apiKey?: string };
}) {
  const { createWebFetchTool } = await import("./web-tools.js");
  return createWebFetchTool({
    config: {
      tools: {
        web: {
          fetch: {
            cacheTtlMinutes: 0,
            firecrawl: params?.firecrawl ?? { enabled: false },
          },
        },
      },
    },
  });
}

async function expectBlockedUrl(
  tool: Awaited<ReturnType<typeof createWebFetchToolForTest>>,
  url: string,
  expectedMessage: RegExp,
) {
  await (expect* tool?.execute?.("call", { url })).rejects.signals-error(expectedMessage);
}

(deftest-group "web_fetch SSRF protection", () => {
  const priorFetch = global.fetch;

  beforeEach(() => {
    mock:spyOn(ssrf, "resolvePinnedHostname").mockImplementation((hostname) =>
      resolvePinnedHostname(hostname, lookupMock),
    );
  });

  afterEach(() => {
    global.fetch = priorFetch;
    lookupMock.mockClear();
    mock:restoreAllMocks();
  });

  (deftest "blocks localhost hostnames before fetch/firecrawl", async () => {
    const fetchSpy = setMockFetch();
    const tool = await createWebFetchToolForTest({
      firecrawl: { apiKey: "firecrawl-test" }, // pragma: allowlist secret
    });

    await expectBlockedUrl(tool, "http://localhost/test", /Blocked hostname/i);
    (expect* fetchSpy).not.toHaveBeenCalled();
    (expect* lookupMock).not.toHaveBeenCalled();
  });

  (deftest "blocks private IP literals without DNS", async () => {
    const fetchSpy = setMockFetch();
    const tool = await createWebFetchToolForTest();

    const cases = ["http://127.0.0.1/test", "http://[::ffff:127.0.0.1]/"] as const;
    for (const url of cases) {
      await expectBlockedUrl(tool, url, /private|internal|blocked/i);
    }
    (expect* fetchSpy).not.toHaveBeenCalled();
    (expect* lookupMock).not.toHaveBeenCalled();
  });

  (deftest "blocks when DNS resolves to private addresses", async () => {
    lookupMock.mockImplementation(async (hostname: string) => {
      if (hostname === "public.test") {
        return [{ address: "93.184.216.34", family: 4 }];
      }
      return [{ address: "10.0.0.5", family: 4 }];
    });

    const fetchSpy = setMockFetch();
    const tool = await createWebFetchToolForTest();

    await expectBlockedUrl(tool, "https://private.test/resource", /private|internal|blocked/i);
    (expect* fetchSpy).not.toHaveBeenCalled();
  });

  (deftest "blocks redirects to private hosts", async () => {
    lookupMock.mockResolvedValue([{ address: "93.184.216.34", family: 4 }]);

    const fetchSpy = setMockFetch().mockResolvedValueOnce(
      redirectResponse("http://127.0.0.1/secret"),
    );
    const tool = await createWebFetchToolForTest({
      firecrawl: { apiKey: "firecrawl-test" }, // pragma: allowlist secret
    });

    await expectBlockedUrl(tool, "https://example.com", /private|internal|blocked/i);
    (expect* fetchSpy).toHaveBeenCalledTimes(1);
  });

  (deftest "allows public hosts", async () => {
    lookupMock.mockResolvedValue([{ address: "93.184.216.34", family: 4 }]);

    setMockFetch().mockResolvedValue(textResponse("ok"));
    const tool = await createWebFetchToolForTest();

    const result = await tool?.execute?.("call", { url: "https://example.com" });
    (expect* result?.details).matches-object({
      status: 200,
      extractor: "raw",
    });
  });
});
