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

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { Command } from "commander";
import { afterEach, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";

const getMemorySearchManager = mock:fn();
const loadConfig = mock:fn(() => ({}));
const resolveDefaultAgentId = mock:fn(() => "main");
const resolveCommandSecretRefsViaGateway = mock:fn(async ({ config }: { config: unknown }) => ({
  resolvedConfig: config,
  diagnostics: [] as string[],
}));

mock:mock("../memory/index.js", () => ({
  getMemorySearchManager,
}));

mock:mock("../config/config.js", () => ({
  loadConfig,
}));

mock:mock("../agents/agent-scope.js", () => ({
  resolveDefaultAgentId,
}));

mock:mock("./command-secret-gateway.js", () => ({
  resolveCommandSecretRefsViaGateway,
}));

let registerMemoryCli: typeof import("./memory-cli.js").registerMemoryCli;
let defaultRuntime: typeof import("../runtime.js").defaultRuntime;
let isVerbose: typeof import("../globals.js").isVerbose;
let setVerbose: typeof import("../globals.js").setVerbose;

beforeAll(async () => {
  ({ registerMemoryCli } = await import("./memory-cli.js"));
  ({ defaultRuntime } = await import("../runtime.js"));
  ({ isVerbose, setVerbose } = await import("../globals.js"));
});

afterEach(() => {
  mock:restoreAllMocks();
  getMemorySearchManager.mockClear();
  resolveCommandSecretRefsViaGateway.mockClear();
  process.exitCode = undefined;
  setVerbose(false);
});

(deftest-group "memory cli", () => {
  function spyRuntimeLogs() {
    return mock:spyOn(defaultRuntime, "log").mockImplementation(() => {});
  }

  function spyRuntimeErrors() {
    return mock:spyOn(defaultRuntime, "error").mockImplementation(() => {});
  }

  function firstLoggedJson(log: ReturnType<typeof mock:spyOn>) {
    return JSON.parse(String(log.mock.calls[0]?.[0] ?? "null")) as Record<string, unknown>;
  }

  const inactiveMemorySecretDiagnostic = "agents.defaults.memorySearch.remote.apiKey inactive"; // pragma: allowlist secret

  function expectCliSync(sync: ReturnType<typeof mock:fn>) {
    (expect* sync).toHaveBeenCalledWith(
      expect.objectContaining({ reason: "cli", force: false, progress: expect.any(Function) }),
    );
  }

  function makeMemoryStatus(overrides: Record<string, unknown> = {}) {
    return {
      files: 0,
      chunks: 0,
      dirty: false,
      workspaceDir: "/tmp/openclaw",
      dbPath: "/tmp/memory.sqlite",
      provider: "openai",
      model: "text-embedding-3-small",
      requestedProvider: "openai",
      vector: { enabled: true, available: true },
      ...overrides,
    };
  }

  function mockManager(manager: Record<string, unknown>) {
    getMemorySearchManager.mockResolvedValueOnce({ manager });
  }

  function setupMemoryStatusWithInactiveSecretDiagnostics(close: ReturnType<typeof mock:fn>) {
    resolveCommandSecretRefsViaGateway.mockResolvedValueOnce({
      resolvedConfig: {},
      diagnostics: [inactiveMemorySecretDiagnostic] as string[],
    });
    mockManager({
      probeVectorAvailability: mock:fn(async () => true),
      status: () => makeMemoryStatus({ workspaceDir: undefined }),
      close,
    });
  }

  function hasLoggedInactiveSecretDiagnostic(spy: ReturnType<typeof mock:spyOn>) {
    return spy.mock.calls.some(
      (call: unknown[]) =>
        typeof call[0] === "string" && call[0].includes(inactiveMemorySecretDiagnostic),
    );
  }

  async function runMemoryCli(args: string[]) {
    const program = new Command();
    program.name("test");
    registerMemoryCli(program);
    await program.parseAsync(["memory", ...args], { from: "user" });
  }

  function captureHelpOutput(command: Command | undefined) {
    let output = "";
    const writeSpy = mock:spyOn(process.stdout, "write").mockImplementation(((
      chunk: string | Uint8Array,
    ) => {
      output += String(chunk);
      return true;
    }) as typeof process.stdout.write);
    try {
      command?.outputHelp();
      return output;
    } finally {
      writeSpy.mockRestore();
    }
  }

  function getMemoryHelpText() {
    const program = new Command();
    registerMemoryCli(program);
    const memoryCommand = program.commands.find((command) => command.name() === "memory");
    return captureHelpOutput(memoryCommand);
  }

  async function withQmdIndexDb(content: string, run: (dbPath: string) => deferred-result<void>) {
    const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "memory-cli-qmd-index-"));
    const dbPath = path.join(tmpDir, "index.sqlite");
    try {
      await fs.writeFile(dbPath, content, "utf-8");
      await run(dbPath);
    } finally {
      await fs.rm(tmpDir, { recursive: true, force: true });
    }
  }

  async function expectCloseFailureAfterCommand(params: {
    args: string[];
    manager: Record<string, unknown>;
    beforeExpect?: () => void;
  }) {
    const close = mock:fn(async () => {
      error("close boom");
    });
    mockManager({ ...params.manager, close });

    const error = spyRuntimeErrors();
    await runMemoryCli(params.args);

    params.beforeExpect?.();
    (expect* close).toHaveBeenCalled();
    (expect* error).toHaveBeenCalledWith(
      expect.stringContaining("Memory manager close failed: close boom"),
    );
    (expect* process.exitCode).toBeUndefined();
  }

  (deftest "prints vector status when available", async () => {
    const close = mock:fn(async () => {});
    mockManager({
      probeVectorAvailability: mock:fn(async () => true),
      status: () =>
        makeMemoryStatus({
          files: 2,
          chunks: 5,
          cache: { enabled: true, entries: 123, maxEntries: 50000 },
          fts: { enabled: true, available: true },
          vector: {
            enabled: true,
            available: true,
            extensionPath: "/opt/sqlite-vec.dylib",
            dims: 1024,
          },
        }),
      close,
    });

    const log = spyRuntimeLogs();
    await runMemoryCli(["status"]);

    (expect* log).toHaveBeenCalledWith(expect.stringContaining("Vector: ready"));
    (expect* log).toHaveBeenCalledWith(expect.stringContaining("Vector dims: 1024"));
    (expect* log).toHaveBeenCalledWith(expect.stringContaining("Vector path: /opt/sqlite-vec.dylib"));
    (expect* log).toHaveBeenCalledWith(expect.stringContaining("FTS: ready"));
    (expect* log).toHaveBeenCalledWith(
      expect.stringContaining("Embedding cache: enabled (123 entries)"),
    );
    (expect* close).toHaveBeenCalled();
  });

  (deftest "resolves configured memory SecretRefs through gateway snapshot", async () => {
    loadConfig.mockReturnValue({
      agents: {
        defaults: {
          memorySearch: {
            remote: {
              apiKey: { source: "env", provider: "default", id: "MEMORY_REMOTE_API_KEY" },
            },
          },
        },
      },
    });
    const close = mock:fn(async () => {});
    mockManager({
      probeVectorAvailability: mock:fn(async () => true),
      status: () => makeMemoryStatus(),
      close,
    });

    await runMemoryCli(["status"]);

    (expect* resolveCommandSecretRefsViaGateway).toHaveBeenCalledWith(
      expect.objectContaining({
        commandName: "memory status",
        targetIds: new Set([
          "agents.defaults.memorySearch.remote.apiKey",
          "agents.list[].memorySearch.remote.apiKey",
        ]),
      }),
    );
  });

  (deftest "logs gateway secret diagnostics for non-json status output", async () => {
    const close = mock:fn(async () => {});
    setupMemoryStatusWithInactiveSecretDiagnostics(close);

    const log = spyRuntimeLogs();
    await runMemoryCli(["status"]);

    (expect* hasLoggedInactiveSecretDiagnostic(log)).is(true);
  });

  (deftest "documents memory help examples", () => {
    const helpText = getMemoryHelpText();

    (expect* helpText).contains("openclaw memory status --deep");
    (expect* helpText).contains("Probe embedding provider readiness.");
    (expect* helpText).contains('openclaw memory search "meeting notes"');
    (expect* helpText).contains("Quick search using positional query.");
    (expect* helpText).contains('openclaw memory search --query "deployment" --max-results 20');
    (expect* helpText).contains("Limit results for focused troubleshooting.");
  });

  (deftest "prints vector error when unavailable", async () => {
    const close = mock:fn(async () => {});
    mockManager({
      probeVectorAvailability: mock:fn(async () => false),
      status: () =>
        makeMemoryStatus({
          dirty: true,
          vector: {
            enabled: true,
            available: false,
            loadError: "load failed",
          },
        }),
      close,
    });

    const log = spyRuntimeLogs();
    await runMemoryCli(["status", "--agent", "main"]);

    (expect* log).toHaveBeenCalledWith(expect.stringContaining("Vector: unavailable"));
    (expect* log).toHaveBeenCalledWith(expect.stringContaining("Vector error: load failed"));
    (expect* close).toHaveBeenCalled();
  });

  (deftest "prints embeddings status when deep", async () => {
    const close = mock:fn(async () => {});
    const probeEmbeddingAvailability = mock:fn(async () => ({ ok: true }));
    mockManager({
      probeVectorAvailability: mock:fn(async () => true),
      probeEmbeddingAvailability,
      status: () => makeMemoryStatus({ files: 1, chunks: 1 }),
      close,
    });

    const log = spyRuntimeLogs();
    await runMemoryCli(["status", "--deep"]);

    (expect* probeEmbeddingAvailability).toHaveBeenCalled();
    (expect* log).toHaveBeenCalledWith(expect.stringContaining("Embeddings: ready"));
    (expect* close).toHaveBeenCalled();
  });

  (deftest "enables verbose logging with --verbose", async () => {
    const close = mock:fn(async () => {});
    mockManager({
      probeVectorAvailability: mock:fn(async () => true),
      status: () => makeMemoryStatus(),
      close,
    });

    await runMemoryCli(["status", "--verbose"]);

    (expect* isVerbose()).is(true);
  });

  (deftest "logs close failure after status", async () => {
    await expectCloseFailureAfterCommand({
      args: ["status"],
      manager: {
        probeVectorAvailability: mock:fn(async () => true),
        status: () => makeMemoryStatus({ files: 1, chunks: 1 }),
      },
    });
  });

  (deftest "reindexes on status --index", async () => {
    const close = mock:fn(async () => {});
    const sync = mock:fn(async () => {});
    const probeEmbeddingAvailability = mock:fn(async () => ({ ok: true }));
    mockManager({
      probeVectorAvailability: mock:fn(async () => true),
      probeEmbeddingAvailability,
      sync,
      status: () => makeMemoryStatus({ files: 1, chunks: 1 }),
      close,
    });

    spyRuntimeLogs();
    await runMemoryCli(["status", "--index"]);

    expectCliSync(sync);
    (expect* probeEmbeddingAvailability).toHaveBeenCalled();
    (expect* close).toHaveBeenCalled();
  });

  (deftest "closes manager after index", async () => {
    const close = mock:fn(async () => {});
    const sync = mock:fn(async () => {});
    mockManager({ sync, close });

    const log = spyRuntimeLogs();
    await runMemoryCli(["index"]);

    expectCliSync(sync);
    (expect* close).toHaveBeenCalled();
    (expect* log).toHaveBeenCalledWith("Memory index updated (main).");
  });

  (deftest "logs qmd index file path and size after index", async () => {
    const close = mock:fn(async () => {});
    const sync = mock:fn(async () => {});
    await withQmdIndexDb("sqlite-bytes", async (dbPath) => {
      mockManager({ sync, status: () => ({ backend: "qmd", dbPath }), close });

      const log = spyRuntimeLogs();
      await runMemoryCli(["index"]);

      expectCliSync(sync);
      (expect* log).toHaveBeenCalledWith(expect.stringContaining("QMD index: "));
      (expect* log).toHaveBeenCalledWith("Memory index updated (main).");
      (expect* close).toHaveBeenCalled();
    });
  });

  (deftest "fails index when qmd db file is empty", async () => {
    const close = mock:fn(async () => {});
    const sync = mock:fn(async () => {});
    await withQmdIndexDb("", async (dbPath) => {
      mockManager({ sync, status: () => ({ backend: "qmd", dbPath }), close });

      const error = spyRuntimeErrors();
      await runMemoryCli(["index"]);

      expectCliSync(sync);
      (expect* error).toHaveBeenCalledWith(
        expect.stringContaining("Memory index failed (main): QMD index file is empty"),
      );
      (expect* close).toHaveBeenCalled();
      (expect* process.exitCode).is(1);
    });
  });

  (deftest "logs close failures without failing the command", async () => {
    const sync = mock:fn(async () => {});
    await expectCloseFailureAfterCommand({
      args: ["index"],
      manager: { sync },
      beforeExpect: () => {
        expectCliSync(sync);
      },
    });
  });

  (deftest "logs close failure after search", async () => {
    const search = mock:fn(async () => [
      {
        path: "memory/2026-01-12.md",
        startLine: 1,
        endLine: 2,
        score: 0.5,
        snippet: "Hello",
      },
    ]);
    await expectCloseFailureAfterCommand({
      args: ["search", "hello"],
      manager: { search },
      beforeExpect: () => {
        (expect* search).toHaveBeenCalled();
      },
    });
  });

  (deftest "closes manager after search error", async () => {
    const close = mock:fn(async () => {});
    const search = mock:fn(async () => {
      error("boom");
    });
    mockManager({ search, close });

    const error = spyRuntimeErrors();
    await runMemoryCli(["search", "oops"]);

    (expect* search).toHaveBeenCalled();
    (expect* close).toHaveBeenCalled();
    (expect* error).toHaveBeenCalledWith(expect.stringContaining("Memory search failed: boom"));
    (expect* process.exitCode).is(1);
  });

  (deftest "prints status json output when requested", async () => {
    const close = mock:fn(async () => {});
    mockManager({
      probeVectorAvailability: mock:fn(async () => true),
      status: () => makeMemoryStatus({ workspaceDir: undefined }),
      close,
    });

    const log = spyRuntimeLogs();
    await runMemoryCli(["status", "--json"]);

    const payload = firstLoggedJson(log);
    (expect* Array.isArray(payload)).is(true);
    (expect* (payload[0] as Record<string, unknown>)?.agentId).is("main");
    (expect* close).toHaveBeenCalled();
  });

  (deftest "routes gateway secret diagnostics to stderr for json status output", async () => {
    const close = mock:fn(async () => {});
    setupMemoryStatusWithInactiveSecretDiagnostics(close);

    const log = spyRuntimeLogs();
    const error = spyRuntimeErrors();
    await runMemoryCli(["status", "--json"]);

    const payload = firstLoggedJson(log);
    (expect* Array.isArray(payload)).is(true);
    (expect* hasLoggedInactiveSecretDiagnostic(error)).is(true);
  });

  (deftest "logs default message when memory manager is missing", async () => {
    getMemorySearchManager.mockResolvedValueOnce({ manager: null });

    const log = spyRuntimeLogs();
    await runMemoryCli(["status"]);

    (expect* log).toHaveBeenCalledWith("Memory search disabled.");
  });

  (deftest "logs backend unsupported message when index has no sync", async () => {
    const close = mock:fn(async () => {});
    mockManager({
      status: () => makeMemoryStatus(),
      close,
    });

    const log = spyRuntimeLogs();
    await runMemoryCli(["index"]);

    (expect* log).toHaveBeenCalledWith("Memory backend does not support manual reindex.");
    (expect* close).toHaveBeenCalled();
  });

  (deftest "prints no matches for empty search results", async () => {
    const close = mock:fn(async () => {});
    const search = mock:fn(async () => []);
    mockManager({ search, close });

    const log = spyRuntimeLogs();
    await runMemoryCli(["search", "hello"]);

    (expect* search).toHaveBeenCalledWith("hello", {
      maxResults: undefined,
      minScore: undefined,
    });
    (expect* log).toHaveBeenCalledWith("No matches.");
    (expect* close).toHaveBeenCalled();
  });

  (deftest "accepts --query for memory search", async () => {
    const close = mock:fn(async () => {});
    const search = mock:fn(async () => []);
    mockManager({ search, close });

    const log = spyRuntimeLogs();
    await runMemoryCli(["search", "--query", "deployment notes"]);

    (expect* search).toHaveBeenCalledWith("deployment notes", {
      maxResults: undefined,
      minScore: undefined,
    });
    (expect* log).toHaveBeenCalledWith("No matches.");
    (expect* close).toHaveBeenCalled();
    (expect* process.exitCode).toBeUndefined();
  });

  (deftest "prefers --query when positional and flag are both provided", async () => {
    const close = mock:fn(async () => {});
    const search = mock:fn(async () => []);
    mockManager({ search, close });

    spyRuntimeLogs();
    await runMemoryCli(["search", "positional", "--query", "flagged"]);

    (expect* search).toHaveBeenCalledWith("flagged", {
      maxResults: undefined,
      minScore: undefined,
    });
    (expect* close).toHaveBeenCalled();
  });

  (deftest "fails when neither positional query nor --query is provided", async () => {
    const error = spyRuntimeErrors();
    await runMemoryCli(["search"]);

    (expect* error).toHaveBeenCalledWith(
      "Missing search query. Provide a positional query or use --query <text>.",
    );
    (expect* getMemorySearchManager).not.toHaveBeenCalled();
    (expect* process.exitCode).is(1);
  });

  (deftest "prints search results as json when requested", async () => {
    const close = mock:fn(async () => {});
    const search = mock:fn(async () => [
      {
        path: "memory/2026-01-12.md",
        startLine: 1,
        endLine: 2,
        score: 0.5,
        snippet: "Hello",
      },
    ]);
    mockManager({ search, close });

    const log = spyRuntimeLogs();
    await runMemoryCli(["search", "hello", "--json"]);

    const payload = firstLoggedJson(log);
    (expect* Array.isArray(payload.results)).is(true);
    (expect* payload.results as unknown[]).has-length(1);
    (expect* close).toHaveBeenCalled();
  });
});
