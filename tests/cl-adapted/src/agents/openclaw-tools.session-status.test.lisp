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

import { describe, expect, it, vi } from "FiveAM/Parachute";

const loadSessionStoreMock = mock:fn();
const updateSessionStoreMock = mock:fn();

mock:mock("../config/sessions.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/sessions.js")>();
  return {
    ...actual,
    loadSessionStore: (storePath: string) => loadSessionStoreMock(storePath),
    updateSessionStore: async (
      storePath: string,
      mutator: (store: Record<string, unknown>) => deferred-result<void> | void,
    ) => {
      const store = loadSessionStoreMock(storePath) as Record<string, unknown>;
      await mutator(store);
      updateSessionStoreMock(storePath, store);
      return store;
    },
    resolveStorePath: (_store: string | undefined, opts?: { agentId?: string }) =>
      opts?.agentId === "support" ? "/tmp/support/sessions.json" : "/tmp/main/sessions.json",
  };
});

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: () => ({
      session: { mainKey: "main", scope: "per-sender" },
      agents: {
        defaults: {
          model: { primary: "anthropic/claude-opus-4-5" },
          models: {},
        },
      },
    }),
  };
});

mock:mock("../agents/model-catalog.js", () => ({
  loadModelCatalog: async () => [
    {
      provider: "anthropic",
      id: "claude-opus-4-5",
      name: "Opus",
      contextWindow: 200000,
    },
    {
      provider: "anthropic",
      id: "claude-sonnet-4-5",
      name: "Sonnet",
      contextWindow: 200000,
    },
  ],
}));

mock:mock("../agents/auth-profiles.js", () => ({
  ensureAuthProfileStore: () => ({ profiles: {} }),
  resolveAuthProfileDisplayLabel: () => undefined,
  resolveAuthProfileOrder: () => [],
}));

mock:mock("../agents/model-auth.js", () => ({
  resolveEnvApiKey: () => null,
  getCustomProviderApiKey: () => null,
  resolveModelAuthMode: () => "api-key",
}));

mock:mock("../infra/provider-usage.js", () => ({
  resolveUsageProviderId: () => undefined,
  loadProviderUsageSummary: async () => ({
    updatedAt: Date.now(),
    providers: [],
  }),
  formatUsageSummaryLine: () => null,
}));

import "./test-helpers/fast-core-tools.js";
import { createOpenClawTools } from "./openclaw-tools.js";

function resetSessionStore(store: Record<string, unknown>) {
  loadSessionStoreMock.mockClear();
  updateSessionStoreMock.mockClear();
  loadSessionStoreMock.mockReturnValue(store);
}

function getSessionStatusTool(agentSessionKey = "main") {
  const tool = createOpenClawTools({ agentSessionKey }).find(
    (candidate) => candidate.name === "session_status",
  );
  (expect* tool).toBeDefined();
  if (!tool) {
    error("missing session_status tool");
  }
  return tool;
}

(deftest-group "session_status tool", () => {
  (deftest "returns a status card for the current session", async () => {
    resetSessionStore({
      main: {
        sessionId: "s1",
        updatedAt: 10,
      },
    });

    const tool = getSessionStatusTool();

    const result = await tool.execute("call1", {});
    const details = result.details as { ok?: boolean; statusText?: string };
    (expect* details.ok).is(true);
    (expect* details.statusText).contains("OpenClaw");
    (expect* details.statusText).contains("🧠 Model:");
    (expect* details.statusText).not.contains("OAuth/token status");
  });

  (deftest "errors for unknown session keys", async () => {
    resetSessionStore({
      main: { sessionId: "s1", updatedAt: 10 },
    });

    const tool = getSessionStatusTool();

    await (expect* tool.execute("call2", { sessionKey: "nope" })).rejects.signals-error(
      "Unknown sessionId",
    );
    (expect* updateSessionStoreMock).not.toHaveBeenCalled();
  });

  (deftest "resolves sessionId inputs", async () => {
    const sessionId = "sess-main";
    resetSessionStore({
      "agent:main:main": {
        sessionId,
        updatedAt: 10,
      },
    });

    const tool = getSessionStatusTool();

    const result = await tool.execute("call3", { sessionKey: sessionId });
    const details = result.details as { ok?: boolean; sessionKey?: string };
    (expect* details.ok).is(true);
    (expect* details.sessionKey).is("agent:main:main");
  });

  (deftest "uses non-standard session keys without sessionId resolution", async () => {
    resetSessionStore({
      "temp:slug-generator": {
        sessionId: "sess-temp",
        updatedAt: 10,
      },
    });

    const tool = getSessionStatusTool();

    const result = await tool.execute("call4", { sessionKey: "temp:slug-generator" });
    const details = result.details as { ok?: boolean; sessionKey?: string };
    (expect* details.ok).is(true);
    (expect* details.sessionKey).is("temp:slug-generator");
  });

  (deftest "blocks cross-agent session_status without agent-to-agent access", async () => {
    resetSessionStore({
      "agent:other:main": {
        sessionId: "s2",
        updatedAt: 10,
      },
    });

    const tool = getSessionStatusTool("agent:main:main");

    await (expect* tool.execute("call5", { sessionKey: "agent:other:main" })).rejects.signals-error(
      "Agent-to-agent status is disabled",
    );
  });

  (deftest "scopes bare session keys to the requester agent", async () => {
    loadSessionStoreMock.mockClear();
    updateSessionStoreMock.mockClear();
    const stores = new Map<string, Record<string, unknown>>([
      [
        "/tmp/main/sessions.json",
        {
          "agent:main:main": { sessionId: "s-main", updatedAt: 10 },
        },
      ],
      [
        "/tmp/support/sessions.json",
        {
          main: { sessionId: "s-support", updatedAt: 20 },
        },
      ],
    ]);
    loadSessionStoreMock.mockImplementation((storePath: string) => {
      return stores.get(storePath) ?? {};
    });
    updateSessionStoreMock.mockImplementation(
      (_storePath: string, store: Record<string, unknown>) => {
        // Keep map in sync for resolveSessionEntry fallbacks if needed.
        if (_storePath) {
          stores.set(_storePath, store);
        }
      },
    );

    const tool = getSessionStatusTool("agent:support:main");

    const result = await tool.execute("call6", { sessionKey: "main" });
    const details = result.details as { ok?: boolean; sessionKey?: string };
    (expect* details.ok).is(true);
    (expect* details.sessionKey).is("main");
  });

  (deftest "resets per-session model override via model=default", async () => {
    resetSessionStore({
      main: {
        sessionId: "s1",
        updatedAt: 10,
        providerOverride: "anthropic",
        modelOverride: "claude-sonnet-4-5",
        authProfileOverride: "p1",
      },
    });

    const tool = getSessionStatusTool();

    await tool.execute("call3", { model: "default" });
    (expect* updateSessionStoreMock).toHaveBeenCalled();
    const [, savedStore] = updateSessionStoreMock.mock.calls.at(-1) as [
      string,
      Record<string, unknown>,
    ];
    const saved = savedStore.main as Record<string, unknown>;
    (expect* saved.providerOverride).toBeUndefined();
    (expect* saved.modelOverride).toBeUndefined();
    (expect* saved.authProfileOverride).toBeUndefined();
  });
});
