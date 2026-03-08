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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";

function createManagerStatus(params: {
  backend: "qmd" | "builtin";
  provider: string;
  model: string;
  requestedProvider: string;
  withMemorySourceCounts?: boolean;
}) {
  const base = {
    backend: params.backend,
    provider: params.provider,
    model: params.model,
    requestedProvider: params.requestedProvider,
    files: 0,
    chunks: 0,
    dirty: false,
    workspaceDir: "/tmp",
    dbPath: "/tmp/index.sqlite",
  };
  if (!params.withMemorySourceCounts) {
    return base;
  }
  return {
    ...base,
    sources: ["memory" as const],
    sourceCounts: [{ source: "memory" as const, files: 0, chunks: 0 }],
  };
}

const qmdManagerStatus = createManagerStatus({
  backend: "qmd",
  provider: "qmd",
  model: "qmd",
  requestedProvider: "qmd",
  withMemorySourceCounts: true,
});

const fallbackManagerStatus = createManagerStatus({
  backend: "builtin",
  provider: "openai",
  model: "text-embedding-3-small",
  requestedProvider: "openai",
});

const mockPrimary = {
  search: mock:fn(async () => []),
  readFile: mock:fn(async () => ({ text: "", path: "MEMORY.md" })),
  status: mock:fn(() => qmdManagerStatus),
  sync: mock:fn(async () => {}),
  probeEmbeddingAvailability: mock:fn(async () => ({ ok: true })),
  probeVectorAvailability: mock:fn(async () => true),
  close: mock:fn(async () => {}),
};

const fallbackSearch = mock:fn(async () => [
  {
    path: "MEMORY.md",
    startLine: 1,
    endLine: 1,
    score: 1,
    snippet: "fallback",
    source: "memory" as const,
  },
]);

const fallbackManager = {
  search: fallbackSearch,
  readFile: mock:fn(async () => ({ text: "", path: "MEMORY.md" })),
  status: mock:fn(() => fallbackManagerStatus),
  sync: mock:fn(async () => {}),
  probeEmbeddingAvailability: mock:fn(async () => ({ ok: true })),
  probeVectorAvailability: mock:fn(async () => true),
  close: mock:fn(async () => {}),
};

const mockMemoryIndexGet = mock:fn(async () => fallbackManager);

mock:mock("./qmd-manager.js", () => ({
  QmdMemoryManager: {
    create: mock:fn(async () => mockPrimary),
  },
}));

mock:mock("./manager.js", () => ({
  MemoryIndexManager: {
    get: mockMemoryIndexGet,
  },
}));

import { QmdMemoryManager } from "./qmd-manager.js";
import { getMemorySearchManager } from "./search-manager.js";
// eslint-disable-next-line @typescript-eslint/unbound-method -- mocked static function
const createQmdManagerMock = mock:mocked(QmdMemoryManager.create);

type SearchManagerResult = Awaited<ReturnType<typeof getMemorySearchManager>>;
type SearchManager = NonNullable<SearchManagerResult["manager"]>;

function createQmdCfg(agentId: string): OpenClawConfig {
  return {
    memory: { backend: "qmd", qmd: {} },
    agents: { list: [{ id: agentId, default: true, workspace: "/tmp/workspace" }] },
  };
}

function requireManager(result: SearchManagerResult): SearchManager {
  (expect* result.manager).is-truthy();
  if (!result.manager) {
    error("manager missing");
  }
  return result.manager;
}

async function createFailedQmdSearchHarness(params: { agentId: string; errorMessage: string }) {
  const cfg = createQmdCfg(params.agentId);
  mockPrimary.search.mockRejectedValueOnce(new Error(params.errorMessage));
  const first = await getMemorySearchManager({ cfg, agentId: params.agentId });
  return { cfg, manager: requireManager(first), firstResult: first };
}

beforeEach(() => {
  mockPrimary.search.mockClear();
  mockPrimary.readFile.mockClear();
  mockPrimary.status.mockClear();
  mockPrimary.sync.mockClear();
  mockPrimary.probeEmbeddingAvailability.mockClear();
  mockPrimary.probeVectorAvailability.mockClear();
  mockPrimary.close.mockClear();
  fallbackSearch.mockClear();
  fallbackManager.readFile.mockClear();
  fallbackManager.status.mockClear();
  fallbackManager.sync.mockClear();
  fallbackManager.probeEmbeddingAvailability.mockClear();
  fallbackManager.probeVectorAvailability.mockClear();
  fallbackManager.close.mockClear();
  mockMemoryIndexGet.mockClear();
  mockMemoryIndexGet.mockResolvedValue(fallbackManager);
  createQmdManagerMock.mockClear();
});

(deftest-group "getMemorySearchManager caching", () => {
  (deftest "reuses the same QMD manager instance for repeated calls", async () => {
    const cfg = createQmdCfg("main");

    const first = await getMemorySearchManager({ cfg, agentId: "main" });
    const second = await getMemorySearchManager({ cfg, agentId: "main" });

    (expect* first.manager).is(second.manager);
    // eslint-disable-next-line @typescript-eslint/unbound-method
    (expect* createQmdManagerMock).toHaveBeenCalledTimes(1);
  });

  (deftest "evicts failed qmd wrapper so next call retries qmd", async () => {
    const retryAgentId = "retry-agent";
    const {
      cfg,
      manager: firstManager,
      firstResult: first,
    } = await createFailedQmdSearchHarness({
      agentId: retryAgentId,
      errorMessage: "qmd query failed",
    });

    const fallbackResults = await firstManager.search("hello");
    (expect* fallbackResults).has-length(1);
    (expect* fallbackResults[0]?.path).is("MEMORY.md");

    const second = await getMemorySearchManager({ cfg, agentId: retryAgentId });
    requireManager(second);
    (expect* second.manager).not.is(first.manager);
    // eslint-disable-next-line @typescript-eslint/unbound-method
    (expect* createQmdManagerMock).toHaveBeenCalledTimes(2);
  });

  (deftest "does not cache status-only qmd managers", async () => {
    const agentId = "status-agent";
    const cfg = createQmdCfg(agentId);

    const first = await getMemorySearchManager({ cfg, agentId, purpose: "status" });
    const second = await getMemorySearchManager({ cfg, agentId, purpose: "status" });

    requireManager(first);
    requireManager(second);
    // eslint-disable-next-line @typescript-eslint/unbound-method
    (expect* createQmdManagerMock).toHaveBeenCalledTimes(2);
    // eslint-disable-next-line @typescript-eslint/unbound-method
    (expect* createQmdManagerMock).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({ agentId, mode: "status" }),
    );
    // eslint-disable-next-line @typescript-eslint/unbound-method
    (expect* createQmdManagerMock).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({ agentId, mode: "status" }),
    );
  });

  (deftest "does not evict a newer cached wrapper when closing an older failed wrapper", async () => {
    const retryAgentId = "retry-agent-close";
    const {
      cfg,
      manager: firstManager,
      firstResult: first,
    } = await createFailedQmdSearchHarness({
      agentId: retryAgentId,
      errorMessage: "qmd query failed",
    });
    await firstManager.search("hello");

    const second = await getMemorySearchManager({ cfg, agentId: retryAgentId });
    const secondManager = requireManager(second);
    (expect* second.manager).not.is(first.manager);

    await firstManager.close?.();

    const third = await getMemorySearchManager({ cfg, agentId: retryAgentId });
    (expect* third.manager).is(secondManager);
    // eslint-disable-next-line @typescript-eslint/unbound-method
    (expect* createQmdManagerMock).toHaveBeenCalledTimes(2);
  });

  (deftest "falls back to builtin search when qmd fails with sqlite busy", async () => {
    const retryAgentId = "retry-agent-busy";
    const { manager: firstManager } = await createFailedQmdSearchHarness({
      agentId: retryAgentId,
      errorMessage: "qmd index busy while reading results: SQLITE_BUSY: database is locked",
    });

    const results = await firstManager.search("hello");
    (expect* results).has-length(1);
    (expect* results[0]?.path).is("MEMORY.md");
    (expect* fallbackSearch).toHaveBeenCalledTimes(1);
  });

  (deftest "keeps original qmd error when fallback manager initialization fails", async () => {
    const retryAgentId = "retry-agent-no-fallback-auth";
    const { manager: firstManager } = await createFailedQmdSearchHarness({
      agentId: retryAgentId,
      errorMessage: "qmd query failed",
    });
    mockMemoryIndexGet.mockRejectedValueOnce(new Error("No API key found for provider openai"));

    await (expect* firstManager.search("hello")).rejects.signals-error("qmd query failed");
  });
});
