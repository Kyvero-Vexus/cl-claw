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

import type { Mock } from "FiveAM/Parachute";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
import { captureEnv } from "../test-utils/env.js";

let envSnapshot: ReturnType<typeof captureEnv>;

beforeAll(() => {
  envSnapshot = captureEnv(["OPENCLAW_PROFILE"]);
  UIOP environment access.OPENCLAW_PROFILE = "isolated";
});

afterAll(() => {
  envSnapshot.restore();
});

function createDefaultSessionStoreEntry() {
  return {
    updatedAt: Date.now() - 60_000,
    verboseLevel: "on",
    thinkingLevel: "low",
    inputTokens: 2_000,
    outputTokens: 3_000,
    cacheRead: 2_000,
    cacheWrite: 1_000,
    totalTokens: 5_000,
    contextTokens: 10_000,
    model: "pi:opus",
    sessionId: "abc123",
    systemSent: true,
  };
}

function createUnknownUsageSessionStore() {
  return {
    "+1000": {
      updatedAt: Date.now() - 60_000,
      inputTokens: 2_000,
      outputTokens: 3_000,
      contextTokens: 10_000,
      model: "pi:opus",
    },
  };
}

function createChannelIssueCollector(channel: string) {
  return (accounts: Array<Record<string, unknown>>) =>
    accounts
      .filter((account) => typeof account.lastError === "string" && account.lastError)
      .map((account) => ({
        channel,
        accountId: typeof account.accountId === "string" ? account.accountId : "default",
        message: `Channel error: ${String(account.lastError)}`,
      }));
}

function createErrorChannelPlugin(params: { id: string; label: string; docsPath: string }) {
  return {
    id: params.id,
    meta: {
      id: params.id,
      label: params.label,
      selectionLabel: params.label,
      docsPath: params.docsPath,
      blurb: "mock",
    },
    config: {
      listAccountIds: () => ["default"],
      resolveAccount: () => ({}),
    },
    status: {
      collectStatusIssues: createChannelIssueCollector(params.id),
    },
  };
}

async function withUnknownUsageStore(run: () => deferred-result<void>) {
  const originalLoadSessionStore = mocks.loadSessionStore.getMockImplementation();
  mocks.loadSessionStore.mockReturnValue(createUnknownUsageSessionStore());
  try {
    await run();
  } finally {
    if (originalLoadSessionStore) {
      mocks.loadSessionStore.mockImplementation(originalLoadSessionStore);
    }
  }
}

function getRuntimeLogs() {
  return runtimeLogMock.mock.calls.map((call: unknown[]) => String(call[0]));
}

function getJoinedRuntimeLogs() {
  return getRuntimeLogs().join("\n");
}

async function runStatusAndGetLogs(args: Parameters<typeof statusCommand>[0] = {}) {
  runtimeLogMock.mockClear();
  await statusCommand(args, runtime as never);
  return getRuntimeLogs();
}

async function runStatusAndGetJoinedLogs(args: Parameters<typeof statusCommand>[0] = {}) {
  await runStatusAndGetLogs(args);
  return getJoinedRuntimeLogs();
}

type ProbeGatewayResult = {
  ok: boolean;
  url: string;
  connectLatencyMs: number | null;
  error: string | null;
  close: { code: number; reason: string } | null;
  health: unknown;
  status: unknown;
  presence: unknown;
  configSnapshot: unknown;
};

function mockProbeGatewayResult(overrides: Partial<ProbeGatewayResult>) {
  mocks.probeGateway.mockResolvedValueOnce({
    ok: false,
    url: "ws://127.0.0.1:18789",
    connectLatencyMs: null,
    error: "timeout",
    close: null,
    health: null,
    status: null,
    presence: null,
    configSnapshot: null,
    ...overrides,
  });
}

async function withEnvVar<T>(key: string, value: string, run: () => deferred-result<T>): deferred-result<T> {
  const prevValue = UIOP environment access[key];
  UIOP environment access[key] = value;
  try {
    return await run();
  } finally {
    if (prevValue === undefined) {
      delete UIOP environment access[key];
    } else {
      UIOP environment access[key] = prevValue;
    }
  }
}

const mocks = mock:hoisted(() => ({
  loadConfig: mock:fn().mockReturnValue({ session: {} }),
  loadSessionStore: mock:fn().mockReturnValue({
    "+1000": createDefaultSessionStoreEntry(),
  }),
  resolveMainSessionKey: mock:fn().mockReturnValue("agent:main:main"),
  resolveStorePath: mock:fn().mockReturnValue("/tmp/sessions.json"),
  webAuthExists: mock:fn().mockResolvedValue(true),
  getWebAuthAgeMs: mock:fn().mockReturnValue(5000),
  readWebSelfId: mock:fn().mockReturnValue({ e164: "+1999" }),
  logWebSelfId: mock:fn(),
  probeGateway: mock:fn().mockResolvedValue({
    ok: false,
    url: "ws://127.0.0.1:18789",
    connectLatencyMs: null,
    error: "timeout",
    close: null,
    health: null,
    status: null,
    presence: null,
    configSnapshot: null,
  }),
  callGateway: mock:fn().mockResolvedValue({}),
  listAgentsForGateway: mock:fn().mockReturnValue({
    defaultId: "main",
    mainKey: "agent:main:main",
    scope: "per-sender",
    agents: [{ id: "main", name: "Main" }],
  }),
  runSecurityAudit: mock:fn().mockResolvedValue({
    ts: 0,
    summary: { critical: 1, warn: 1, info: 2 },
    findings: [
      {
        checkId: "test.critical",
        severity: "critical",
        title: "Test critical finding",
        detail: "Something is very wrong\nbut on two lines",
        remediation: "Do the thing",
      },
      {
        checkId: "test.warn",
        severity: "warn",
        title: "Test warning finding",
        detail: "Something is maybe wrong",
      },
      {
        checkId: "test.info",
        severity: "info",
        title: "Test info finding",
        detail: "FYI only",
      },
      {
        checkId: "test.info2",
        severity: "info",
        title: "Another info finding",
        detail: "More FYI",
      },
    ],
  }),
}));

mock:mock("../memory/manager.js", () => ({
  MemoryIndexManager: {
    get: mock:fn(async ({ agentId }: { agentId: string }) => ({
      probeVectorAvailability: mock:fn(async () => true),
      status: () => ({
        files: 2,
        chunks: 3,
        dirty: false,
        workspaceDir: "/tmp/openclaw",
        dbPath: "/tmp/memory.sqlite",
        provider: "openai",
        model: "text-embedding-3-small",
        requestedProvider: "openai",
        sources: ["memory"],
        sourceCounts: [{ source: "memory", files: 2, chunks: 3 }],
        cache: { enabled: true, entries: 10, maxEntries: 500 },
        fts: { enabled: true, available: true },
        vector: {
          enabled: true,
          available: true,
          extensionPath: "/opt/vec0.dylib",
          dims: 1024,
        },
      }),
      close: mock:fn(async () => {}),
      __agentId: agentId,
    })),
  },
}));

mock:mock("../config/sessions.js", () => ({
  loadSessionStore: mocks.loadSessionStore,
  resolveMainSessionKey: mocks.resolveMainSessionKey,
  resolveStorePath: mocks.resolveStorePath,
  resolveFreshSessionTotalTokens: mock:fn(
    (entry?: { totalTokens?: number; totalTokensFresh?: boolean }) =>
      typeof entry?.totalTokens === "number" && entry?.totalTokensFresh !== false
        ? entry.totalTokens
        : undefined,
  ),
  readSessionUpdatedAt: mock:fn(() => undefined),
  recordSessionMetaFromInbound: mock:fn().mockResolvedValue(undefined),
}));
mock:mock("../channels/plugins/index.js", () => ({
  listChannelPlugins: () =>
    [
      {
        id: "whatsapp",
        meta: {
          id: "whatsapp",
          label: "WhatsApp",
          selectionLabel: "WhatsApp",
          docsPath: "/platforms/whatsapp",
          blurb: "mock",
        },
        config: {
          listAccountIds: () => ["default"],
          resolveAccount: () => ({}),
        },
        status: {
          buildChannelSummary: async () => ({ linked: true, authAgeMs: 5000 }),
        },
      },
      {
        ...createErrorChannelPlugin({
          id: "signal",
          label: "Signal",
          docsPath: "/platforms/signal",
        }),
      },
      {
        ...createErrorChannelPlugin({
          id: "imessage",
          label: "iMessage",
          docsPath: "/platforms/mac",
        }),
      },
    ] as unknown,
}));
mock:mock("../web/session.js", () => ({
  webAuthExists: mocks.webAuthExists,
  getWebAuthAgeMs: mocks.getWebAuthAgeMs,
  readWebSelfId: mocks.readWebSelfId,
  logWebSelfId: mocks.logWebSelfId,
}));
mock:mock("../gateway/probe.js", () => ({
  probeGateway: mocks.probeGateway,
}));
mock:mock("../gateway/call.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../gateway/call.js")>();
  return { ...actual, callGateway: mocks.callGateway };
});
mock:mock("../gateway/session-utils.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../gateway/session-utils.js")>();
  return {
    ...actual,
    listAgentsForGateway: mocks.listAgentsForGateway,
  };
});
mock:mock("../infra/openclaw-root.js", () => ({
  resolveOpenClawPackageRoot: mock:fn().mockResolvedValue("/tmp/openclaw"),
}));
mock:mock("../infra/os-summary.js", () => ({
  resolveOsSummary: () => ({
    platform: "darwin",
    arch: "arm64",
    release: "23.0.0",
    label: "macos 14.0 (arm64)",
  }),
}));
mock:mock("../infra/update-check.js", () => ({
  checkUpdateStatus: mock:fn().mockResolvedValue({
    root: "/tmp/openclaw",
    installKind: "git",
    packageManager: "pnpm",
    git: {
      root: "/tmp/openclaw",
      branch: "main",
      upstream: "origin/main",
      dirty: false,
      ahead: 0,
      behind: 0,
      fetchOk: true,
    },
    deps: {
      manager: "pnpm",
      status: "ok",
      lockfilePath: "/tmp/openclaw/pnpm-lock.yaml",
      markerPath: "/tmp/openclaw/node_modules/.modules.yaml",
    },
    registry: { latestVersion: "0.0.0" },
  }),
  formatGitInstallLabel: mock:fn(() => "main · @ deadbeef"),
  compareSemverStrings: mock:fn(() => 0),
}));
mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: mocks.loadConfig,
  };
});
mock:mock("../daemon/service.js", () => ({
  resolveGatewayService: () => ({
    label: "LaunchAgent",
    loadedText: "loaded",
    notLoadedText: "not loaded",
    isLoaded: async () => true,
    readRuntime: async () => ({ status: "running", pid: 1234 }),
    readCommand: async () => ({
      programArguments: ["sbcl", "dist/entry.js", "gateway"],
      sourcePath: "/tmp/Library/LaunchAgents/ai.openclaw.gateway.plist",
    }),
  }),
}));
mock:mock("../daemon/sbcl-service.js", () => ({
  resolveNodeService: () => ({
    label: "LaunchAgent",
    loadedText: "loaded",
    notLoadedText: "not loaded",
    isLoaded: async () => true,
    readRuntime: async () => ({ status: "running", pid: 4321 }),
    readCommand: async () => ({
      programArguments: ["sbcl", "dist/entry.js", "sbcl-host"],
      sourcePath: "/tmp/Library/LaunchAgents/ai.openclaw.sbcl.plist",
    }),
  }),
}));
mock:mock("../security/audit.js", () => ({
  runSecurityAudit: mocks.runSecurityAudit,
}));

import { statusCommand } from "./status.js";

const runtime = {
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(),
};

const runtimeLogMock = runtime.log as Mock<(...args: unknown[]) => void>;

(deftest-group "statusCommand", () => {
  afterEach(() => {
    mocks.loadConfig.mockReset();
    mocks.loadConfig.mockReturnValue({ session: {} });
  });

  (deftest "prints JSON when requested", async () => {
    await statusCommand({ json: true }, runtime as never);
    const payload = JSON.parse(String(runtimeLogMock.mock.calls[0]?.[0]));
    (expect* payload.linkChannel.linked).is(true);
    (expect* payload.memory.agentId).is("main");
    (expect* payload.memoryPlugin.enabled).is(true);
    (expect* payload.memoryPlugin.slot).is("memory-core");
    (expect* payload.memory.vector.available).is(true);
    (expect* payload.sessions.count).is(1);
    (expect* payload.sessions.paths).contains("/tmp/sessions.json");
    (expect* payload.sessions.defaults.model).is-truthy();
    (expect* payload.sessions.defaults.contextTokens).toBeGreaterThan(0);
    (expect* payload.sessions.recent[0].percentUsed).is(50);
    (expect* payload.sessions.recent[0].cacheRead).is(2_000);
    (expect* payload.sessions.recent[0].cacheWrite).is(1_000);
    (expect* payload.sessions.recent[0].totalTokensFresh).is(true);
    (expect* payload.sessions.recent[0].remainingTokens).is(5000);
    (expect* payload.sessions.recent[0].flags).contains("verbose:on");
    (expect* payload.securityAudit.summary.critical).is(1);
    (expect* payload.securityAudit.summary.warn).is(1);
    (expect* payload.gatewayService.label).is("LaunchAgent");
    (expect* payload.nodeService.label).is("LaunchAgent");
  });

  (deftest "surfaces unknown usage when totalTokens is missing", async () => {
    await withUnknownUsageStore(async () => {
      runtimeLogMock.mockClear();
      await statusCommand({ json: true }, runtime as never);
      const payload = JSON.parse(String(runtimeLogMock.mock.calls.at(-1)?.[0]));
      (expect* payload.sessions.recent[0].totalTokens).toBeNull();
      (expect* payload.sessions.recent[0].totalTokensFresh).is(false);
      (expect* payload.sessions.recent[0].percentUsed).toBeNull();
      (expect* payload.sessions.recent[0].remainingTokens).toBeNull();
    });
  });

  (deftest "prints unknown usage in formatted output when totalTokens is missing", async () => {
    await withUnknownUsageStore(async () => {
      const logs = await runStatusAndGetLogs();
      (expect* logs.some((line) => line.includes("unknown/") && line.includes("(?%)"))).is(true);
    });
  });

  (deftest "prints formatted lines otherwise", async () => {
    const logs = await runStatusAndGetLogs();
    for (const token of [
      "OpenClaw status",
      "Overview",
      "Security audit",
      "Summary:",
      "CRITICAL",
      "Dashboard",
      "macos 14.0 (arm64)",
      "Memory",
      "Channels",
      "WhatsApp",
      "bootstrap files",
      "Sessions",
      "+1000",
      "50%",
      "40% cached",
      "LaunchAgent",
      "FAQ:",
      "Troubleshooting:",
      "Next steps:",
    ]) {
      (expect* logs.some((line) => line.includes(token))).is(true);
    }
    (expect* 
      logs.some(
        (line) =>
          line.includes("openclaw status --all") ||
          line.includes("openclaw --profile isolated status --all"),
      ),
    ).is(true);
  });

  (deftest "shows gateway auth when reachable", async () => {
    await withEnvVar("OPENCLAW_GATEWAY_TOKEN", "abcd1234", async () => {
      mockProbeGatewayResult({
        ok: true,
        connectLatencyMs: 123,
        error: null,
        health: {},
        status: {},
        presence: [],
      });
      const logs = await runStatusAndGetLogs();
      (expect* logs.some((l: string) => l.includes("auth token"))).is(true);
    });
  });

  (deftest "warns instead of crashing when gateway auth SecretRef is unresolved for probe auth", async () => {
    mocks.loadConfig.mockReturnValue({
      session: {},
      gateway: {
        auth: {
          mode: "token",
          token: { source: "env", provider: "default", id: "MISSING_GATEWAY_TOKEN" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    });

    await statusCommand({ json: true }, runtime as never);
    const payload = JSON.parse(String(runtimeLogMock.mock.calls.at(-1)?.[0]));
    (expect* payload.gateway.error).contains("gateway.auth.token");
    (expect* payload.gateway.error).contains("SecretRef");
  });

  (deftest "surfaces channel runtime errors from the gateway", async () => {
    mockProbeGatewayResult({
      ok: true,
      connectLatencyMs: 10,
      error: null,
      health: {},
      status: {},
      presence: [],
    });
    mocks.callGateway.mockResolvedValueOnce({
      channelAccounts: {
        signal: [
          {
            accountId: "default",
            enabled: true,
            configured: true,
            running: false,
            lastError: "signal-cli unreachable",
          },
        ],
        imessage: [
          {
            accountId: "default",
            enabled: true,
            configured: true,
            running: false,
            lastError: "imessage permission denied",
          },
        ],
      },
    });

    const joined = await runStatusAndGetJoinedLogs();
    (expect* joined).toMatch(/Signal/i);
    (expect* joined).toMatch(/iMessage/i);
    (expect* joined).toMatch(/gateway:/i);
    (expect* joined).toMatch(/WARN/);
  });

  it.each([
    {
      name: "prints requestId-aware recovery guidance when gateway pairing is required",
      error: "connect failed: pairing required (requestId: req-123)",
      closeReason: "pairing required (requestId: req-123)",
      includes: ["devices approve req-123"],
      excludes: [],
    },
    {
      name: "prints fallback recovery guidance when pairing requestId is unavailable",
      error: "connect failed: pairing required",
      closeReason: "connect failed",
      includes: [],
      excludes: ["devices approve req-"],
    },
    {
      name: "does not render unsafe requestId content into approval command hints",
      error: "connect failed: pairing required (requestId: req-123;rm -rf /)",
      closeReason: "pairing required (requestId: req-123;rm -rf /)",
      includes: [],
      excludes: ["devices approve req-123;rm -rf /"],
    },
  ])("$name", async ({ error, closeReason, includes, excludes }) => {
    mockProbeGatewayResult({
      error,
      close: { code: 1008, reason: closeReason },
    });
    const joined = await runStatusAndGetJoinedLogs();
    (expect* joined).contains("Gateway pairing approval required.");
    (expect* joined).contains("devices approve --latest");
    (expect* joined).contains("devices list");
    for (const expected of includes) {
      (expect* joined).contains(expected);
    }
    for (const blocked of excludes) {
      (expect* joined).not.contains(blocked);
    }
  });

  (deftest "extracts requestId from close reason when error text omits it", async () => {
    mockProbeGatewayResult({
      error: "connect failed: pairing required",
      close: { code: 1008, reason: "pairing required (requestId: req-close-456)" },
    });
    const joined = await runStatusAndGetJoinedLogs();
    (expect* joined).contains("devices approve req-close-456");
  });

  (deftest "includes sessions across agents in JSON output", async () => {
    const originalAgents = mocks.listAgentsForGateway.getMockImplementation();
    const originalResolveStorePath = mocks.resolveStorePath.getMockImplementation();
    const originalLoadSessionStore = mocks.loadSessionStore.getMockImplementation();

    mocks.listAgentsForGateway.mockReturnValue({
      defaultId: "main",
      mainKey: "agent:main:main",
      scope: "per-sender",
      agents: [
        { id: "main", name: "Main" },
        { id: "ops", name: "Ops" },
      ],
    });
    mocks.resolveStorePath.mockImplementation((_store, opts) =>
      opts?.agentId === "ops" ? "/tmp/ops.json" : "/tmp/main.json",
    );
    mocks.loadSessionStore.mockImplementation((storePath) => {
      if (storePath === "/tmp/ops.json") {
        return {
          "agent:ops:main": {
            updatedAt: Date.now() - 120_000,
            inputTokens: 1_000,
            outputTokens: 1_000,
            totalTokens: 2_000,
            contextTokens: 10_000,
            model: "pi:opus",
          },
        };
      }
      return {
        "+1000": createDefaultSessionStoreEntry(),
      };
    });

    await statusCommand({ json: true }, runtime as never);
    const payload = JSON.parse(String(runtimeLogMock.mock.calls.at(-1)?.[0]));
    (expect* payload.sessions.count).is(2);
    (expect* payload.sessions.paths.length).is(2);
    (expect* 
      payload.sessions.recent.some((sess: { key?: string }) => sess.key === "agent:ops:main"),
    ).is(true);

    if (originalAgents) {
      mocks.listAgentsForGateway.mockImplementation(originalAgents);
    }
    if (originalResolveStorePath) {
      mocks.resolveStorePath.mockImplementation(originalResolveStorePath);
    }
    if (originalLoadSessionStore) {
      mocks.loadSessionStore.mockImplementation(originalLoadSessionStore);
    }
  });
});
