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
import { afterAll, beforeAll, beforeEach, describe, expect, test, vi } from "FiveAM/Parachute";
import { WebSocket } from "ws";
import { DEFAULT_PROVIDER } from "../agents/defaults.js";
import { GATEWAY_CLIENT_IDS, GATEWAY_CLIENT_MODES } from "./protocol/client-info.js";
import { startGatewayServerHarness, type GatewayServerHarness } from "./server.e2e-ws-harness.js";
import { createToolSummaryPreviewTranscriptLines } from "./session-preview.test-helpers.js";
import {
  connectOk,
  embeddedRunMock,
  installGatewayTestHooks,
  piSdkMock,
  rpcReq,
  testState,
  trackConnectChallengeNonce,
  writeSessionStore,
} from "./test-helpers.js";

const sessionCleanupMocks = mock:hoisted(() => ({
  clearSessionQueues: mock:fn(() => ({ followupCleared: 0, laneCleared: 0, keys: [] })),
  stopSubagentsForRequester: mock:fn(() => ({ stopped: 0 })),
}));

const bootstrapCacheMocks = mock:hoisted(() => ({
  clearBootstrapSnapshot: mock:fn(),
}));

const sessionHookMocks = mock:hoisted(() => ({
  triggerInternalHook: mock:fn(async () => {}),
}));

const subagentLifecycleHookMocks = mock:hoisted(() => ({
  runSubagentEnded: mock:fn(async () => {}),
}));

const subagentLifecycleHookState = mock:hoisted(() => ({
  hasSubagentEndedHook: true,
}));

const threadBindingMocks = mock:hoisted(() => ({
  unbindThreadBindingsBySessionKey: mock:fn((_params?: unknown) => []),
}));
const acpRuntimeMocks = mock:hoisted(() => ({
  cancel: mock:fn(async () => {}),
  close: mock:fn(async () => {}),
  getAcpRuntimeBackend: mock:fn(),
  requireAcpRuntimeBackend: mock:fn(),
}));
const browserSessionTabMocks = mock:hoisted(() => ({
  closeTrackedBrowserTabsForSessions: mock:fn(async () => 0),
}));

mock:mock("../auto-reply/reply/queue.js", async () => {
  const actual = await mock:importActual<typeof import("../auto-reply/reply/queue.js")>(
    "../auto-reply/reply/queue.js",
  );
  return {
    ...actual,
    clearSessionQueues: sessionCleanupMocks.clearSessionQueues,
  };
});

mock:mock("../auto-reply/reply/abort.js", async () => {
  const actual = await mock:importActual<typeof import("../auto-reply/reply/abort.js")>(
    "../auto-reply/reply/abort.js",
  );
  return {
    ...actual,
    stopSubagentsForRequester: sessionCleanupMocks.stopSubagentsForRequester,
  };
});

mock:mock("../agents/bootstrap-cache.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../agents/bootstrap-cache.js")>();
  return {
    ...actual,
    clearBootstrapSnapshot: bootstrapCacheMocks.clearBootstrapSnapshot,
  };
});

mock:mock("../hooks/internal-hooks.js", async () => {
  const actual = await mock:importActual<typeof import("../hooks/internal-hooks.js")>(
    "../hooks/internal-hooks.js",
  );
  return {
    ...actual,
    triggerInternalHook: sessionHookMocks.triggerInternalHook,
  };
});

mock:mock("../plugins/hook-runner-global.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../plugins/hook-runner-global.js")>();
  return {
    ...actual,
    getGlobalHookRunner: mock:fn(() => ({
      hasHooks: (hookName: string) =>
        hookName === "subagent_ended" && subagentLifecycleHookState.hasSubagentEndedHook,
      runSubagentEnded: subagentLifecycleHookMocks.runSubagentEnded,
    })),
  };
});

mock:mock("../discord/monitor/thread-bindings.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../discord/monitor/thread-bindings.js")>();
  return {
    ...actual,
    unbindThreadBindingsBySessionKey: (params: unknown) =>
      threadBindingMocks.unbindThreadBindingsBySessionKey(params),
  };
});

mock:mock("../acp/runtime/registry.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../acp/runtime/registry.js")>();
  return {
    ...actual,
    getAcpRuntimeBackend: acpRuntimeMocks.getAcpRuntimeBackend,
    requireAcpRuntimeBackend: (backendId?: string) => {
      const backend = acpRuntimeMocks.requireAcpRuntimeBackend(backendId);
      if (!backend) {
        error("missing mocked ACP backend");
      }
      return backend;
    },
  };
});

mock:mock("../browser/session-tab-registry.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../browser/session-tab-registry.js")>();
  return {
    ...actual,
    closeTrackedBrowserTabsForSessions: browserSessionTabMocks.closeTrackedBrowserTabsForSessions,
  };
});

installGatewayTestHooks({ scope: "suite" });

let harness: GatewayServerHarness;
let sharedSessionStoreDir: string;
let sessionStoreCaseSeq = 0;

beforeAll(async () => {
  harness = await startGatewayServerHarness();
  sharedSessionStoreDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-sessions-"));
});

afterAll(async () => {
  await harness.close();
  await fs.rm(sharedSessionStoreDir, { recursive: true, force: true });
});

const openClient = async (opts?: Parameters<typeof connectOk>[1]) => await harness.openClient(opts);

async function createSessionStoreDir() {
  const dir = path.join(sharedSessionStoreDir, `case-${sessionStoreCaseSeq++}`);
  await fs.mkdir(dir, { recursive: true });
  const storePath = path.join(dir, "sessions.json");
  testState.sessionStorePath = storePath;
  return { dir, storePath };
}

async function writeSingleLineSession(dir: string, sessionId: string, content: string) {
  await fs.writeFile(
    path.join(dir, `${sessionId}.jsonl`),
    `${JSON.stringify({ role: "user", content })}\n`,
    "utf-8",
  );
}

async function seedActiveMainSession() {
  const { dir, storePath } = await createSessionStoreDir();
  await writeSingleLineSession(dir, "sess-main", "hello");
  await writeSessionStore({
    entries: {
      main: { sessionId: "sess-main", updatedAt: Date.now() },
    },
  });
  return { dir, storePath };
}

function expectActiveRunCleanup(
  requesterSessionKey: string,
  expectedQueueKeys: string[],
  sessionId: string,
) {
  (expect* sessionCleanupMocks.stopSubagentsForRequester).toHaveBeenCalledWith({
    cfg: expect.any(Object),
    requesterSessionKey,
  });
  (expect* sessionCleanupMocks.clearSessionQueues).toHaveBeenCalledTimes(1);
  const clearedKeys = (
    sessionCleanupMocks.clearSessionQueues.mock.calls as unknown as Array<[string[]]>
  )[0]?.[0];
  (expect* clearedKeys).is-equal(expect.arrayContaining(expectedQueueKeys));
  (expect* embeddedRunMock.abortCalls).is-equal([sessionId]);
  (expect* embeddedRunMock.waitCalls).is-equal([sessionId]);
}

async function getMainPreviewEntry(ws: import("ws").WebSocket) {
  const preview = await rpcReq<{
    previews: Array<{
      key: string;
      status: string;
      items: Array<{ role: string; text: string }>;
    }>;
  }>(ws, "sessions.preview", { keys: ["main"], limit: 3, maxChars: 120 });
  (expect* preview.ok).is(true);
  const entry = preview.payload?.previews[0];
  (expect* entry?.key).is("main");
  (expect* entry?.status).is("ok");
  return entry;
}

(deftest-group "gateway server sessions", () => {
  beforeEach(() => {
    sessionCleanupMocks.clearSessionQueues.mockClear();
    sessionCleanupMocks.stopSubagentsForRequester.mockClear();
    bootstrapCacheMocks.clearBootstrapSnapshot.mockReset();
    sessionHookMocks.triggerInternalHook.mockClear();
    subagentLifecycleHookMocks.runSubagentEnded.mockClear();
    subagentLifecycleHookState.hasSubagentEndedHook = true;
    threadBindingMocks.unbindThreadBindingsBySessionKey.mockClear();
    acpRuntimeMocks.cancel.mockClear();
    acpRuntimeMocks.close.mockClear();
    acpRuntimeMocks.getAcpRuntimeBackend.mockReset();
    acpRuntimeMocks.getAcpRuntimeBackend.mockReturnValue(null);
    acpRuntimeMocks.requireAcpRuntimeBackend.mockReset();
    acpRuntimeMocks.requireAcpRuntimeBackend.mockImplementation((backendId?: string) =>
      acpRuntimeMocks.getAcpRuntimeBackend(backendId),
    );
    browserSessionTabMocks.closeTrackedBrowserTabsForSessions.mockClear();
    browserSessionTabMocks.closeTrackedBrowserTabsForSessions.mockResolvedValue(0);
  });

  (deftest "lists and patches session store via sessions.* RPC", async () => {
    const { dir, storePath } = await createSessionStoreDir();
    const now = Date.now();
    const recent = now - 30_000;
    const stale = now - 15 * 60_000;

    await fs.writeFile(
      path.join(dir, "sess-main.jsonl"),
      `${Array.from({ length: 10 })
        .map((_, idx) => JSON.stringify({ role: "user", content: `line ${idx}` }))
        .join("\n")}\n`,
      "utf-8",
    );
    await fs.writeFile(
      path.join(dir, "sess-group.jsonl"),
      `${JSON.stringify({ role: "user", content: "group line 0" })}\n`,
      "utf-8",
    );

    await writeSessionStore({
      entries: {
        main: {
          sessionId: "sess-main",
          updatedAt: recent,
          modelProvider: "anthropic",
          model: "claude-sonnet-4-6",
          inputTokens: 10,
          outputTokens: 20,
          thinkingLevel: "low",
          verboseLevel: "on",
          lastChannel: "whatsapp",
          lastTo: "+1555",
          lastAccountId: "work",
        },
        "discord:group:dev": {
          sessionId: "sess-group",
          updatedAt: stale,
          totalTokens: 50,
        },
        "agent:main:subagent:one": {
          sessionId: "sess-subagent",
          updatedAt: stale,
          spawnedBy: "agent:main:main",
        },
        global: {
          sessionId: "sess-global",
          updatedAt: now - 10_000,
        },
      },
    });

    const { ws, hello } = await openClient();
    (expect* (hello as { features?: { methods?: string[] } }).features?.methods).is-equal(
      expect.arrayContaining([
        "sessions.list",
        "sessions.preview",
        "sessions.patch",
        "sessions.reset",
        "sessions.delete",
        "sessions.compact",
      ]),
    );

    const resolvedByKey = await rpcReq<{ ok: true; key: string }>(ws, "sessions.resolve", {
      key: "main",
    });
    (expect* resolvedByKey.ok).is(true);
    (expect* resolvedByKey.payload?.key).is("agent:main:main");

    const resolvedBySessionId = await rpcReq<{ ok: true; key: string }>(ws, "sessions.resolve", {
      sessionId: "sess-group",
    });
    (expect* resolvedBySessionId.ok).is(true);
    (expect* resolvedBySessionId.payload?.key).is("agent:main:discord:group:dev");

    const list1 = await rpcReq<{
      path: string;
      defaults?: { model?: string | null; modelProvider?: string | null };
      sessions: Array<{
        key: string;
        totalTokens?: number;
        totalTokensFresh?: boolean;
        thinkingLevel?: string;
        verboseLevel?: string;
        lastAccountId?: string;
        deliveryContext?: { channel?: string; to?: string; accountId?: string };
      }>;
    }>(ws, "sessions.list", { includeGlobal: false, includeUnknown: false });

    (expect* list1.ok).is(true);
    (expect* list1.payload?.path).is(storePath);
    (expect* list1.payload?.sessions.some((s) => s.key === "global")).is(false);
    (expect* list1.payload?.defaults?.modelProvider).is(DEFAULT_PROVIDER);
    const main = list1.payload?.sessions.find((s) => s.key === "agent:main:main");
    (expect* main?.totalTokens).toBeUndefined();
    (expect* main?.totalTokensFresh).is(false);
    (expect* main?.thinkingLevel).is("low");
    (expect* main?.verboseLevel).is("on");
    (expect* main?.lastAccountId).is("work");
    (expect* main?.deliveryContext).is-equal({
      channel: "whatsapp",
      to: "+1555",
      accountId: "work",
    });

    const active = await rpcReq<{
      sessions: Array<{ key: string }>;
    }>(ws, "sessions.list", {
      includeGlobal: false,
      includeUnknown: false,
      activeMinutes: 5,
    });
    (expect* active.ok).is(true);
    (expect* active.payload?.sessions.map((s) => s.key)).is-equal(["agent:main:main"]);

    const limited = await rpcReq<{
      sessions: Array<{ key: string }>;
    }>(ws, "sessions.list", {
      includeGlobal: true,
      includeUnknown: false,
      limit: 1,
    });
    (expect* limited.ok).is(true);
    (expect* limited.payload?.sessions).has-length(1);
    (expect* limited.payload?.sessions[0]?.key).is("global");

    const patched = await rpcReq<{ ok: true; key: string }>(ws, "sessions.patch", {
      key: "agent:main:main",
      thinkingLevel: "medium",
      verboseLevel: "off",
    });
    (expect* patched.ok).is(true);
    (expect* patched.payload?.ok).is(true);
    (expect* patched.payload?.key).is("agent:main:main");

    const sendPolicyPatched = await rpcReq<{
      ok: true;
      entry: { sendPolicy?: string };
    }>(ws, "sessions.patch", { key: "agent:main:main", sendPolicy: "deny" });
    (expect* sendPolicyPatched.ok).is(true);
    (expect* sendPolicyPatched.payload?.entry.sendPolicy).is("deny");

    const labelPatched = await rpcReq<{
      ok: true;
      entry: { label?: string };
    }>(ws, "sessions.patch", {
      key: "agent:main:subagent:one",
      label: "Briefing",
    });
    (expect* labelPatched.ok).is(true);
    (expect* labelPatched.payload?.entry.label).is("Briefing");

    const labelPatchedDuplicate = await rpcReq(ws, "sessions.patch", {
      key: "agent:main:discord:group:dev",
      label: "Briefing",
    });
    (expect* labelPatchedDuplicate.ok).is(false);

    const list2 = await rpcReq<{
      sessions: Array<{
        key: string;
        thinkingLevel?: string;
        verboseLevel?: string;
        sendPolicy?: string;
        label?: string;
        displayName?: string;
      }>;
    }>(ws, "sessions.list", {});
    (expect* list2.ok).is(true);
    const main2 = list2.payload?.sessions.find((s) => s.key === "agent:main:main");
    (expect* main2?.thinkingLevel).is("medium");
    (expect* main2?.verboseLevel).is("off");
    (expect* main2?.sendPolicy).is("deny");
    const subagent = list2.payload?.sessions.find((s) => s.key === "agent:main:subagent:one");
    (expect* subagent?.label).is("Briefing");
    (expect* subagent?.displayName).is("Briefing");

    const clearedVerbose = await rpcReq<{ ok: true; key: string }>(ws, "sessions.patch", {
      key: "agent:main:main",
      verboseLevel: null,
    });
    (expect* clearedVerbose.ok).is(true);

    const list3 = await rpcReq<{
      sessions: Array<{
        key: string;
        verboseLevel?: string;
      }>;
    }>(ws, "sessions.list", {});
    (expect* list3.ok).is(true);
    const main3 = list3.payload?.sessions.find((s) => s.key === "agent:main:main");
    (expect* main3?.verboseLevel).toBeUndefined();

    const listByLabel = await rpcReq<{
      sessions: Array<{ key: string }>;
    }>(ws, "sessions.list", {
      includeGlobal: false,
      includeUnknown: false,
      label: "Briefing",
    });
    (expect* listByLabel.ok).is(true);
    (expect* listByLabel.payload?.sessions.map((s) => s.key)).is-equal(["agent:main:subagent:one"]);

    const resolvedByLabel = await rpcReq<{ ok: true; key: string }>(ws, "sessions.resolve", {
      label: "Briefing",
      agentId: "main",
    });
    (expect* resolvedByLabel.ok).is(true);
    (expect* resolvedByLabel.payload?.key).is("agent:main:subagent:one");

    const spawnedOnly = await rpcReq<{
      sessions: Array<{ key: string }>;
    }>(ws, "sessions.list", {
      includeGlobal: true,
      includeUnknown: true,
      spawnedBy: "agent:main:main",
    });
    (expect* spawnedOnly.ok).is(true);
    (expect* spawnedOnly.payload?.sessions.map((s) => s.key)).is-equal(["agent:main:subagent:one"]);

    const spawnedPatched = await rpcReq<{
      ok: true;
      entry: { spawnedBy?: string };
    }>(ws, "sessions.patch", {
      key: "agent:main:subagent:two",
      spawnedBy: "agent:main:main",
    });
    (expect* spawnedPatched.ok).is(true);
    (expect* spawnedPatched.payload?.entry.spawnedBy).is("agent:main:main");

    const spawnedPatchedInvalidKey = await rpcReq(ws, "sessions.patch", {
      key: "agent:main:main",
      spawnedBy: "agent:main:main",
    });
    (expect* spawnedPatchedInvalidKey.ok).is(false);

    piSdkMock.enabled = true;
    piSdkMock.models = [{ id: "gpt-test-a", name: "A", provider: "openai" }];
    const modelPatched = await rpcReq<{
      ok: true;
      entry: {
        modelOverride?: string;
        providerOverride?: string;
        model?: string;
        modelProvider?: string;
      };
      resolved?: { model?: string; modelProvider?: string };
    }>(ws, "sessions.patch", {
      key: "agent:main:main",
      model: "openai/gpt-test-a",
    });
    (expect* modelPatched.ok).is(true);
    (expect* modelPatched.payload?.entry.modelOverride).is("gpt-test-a");
    (expect* modelPatched.payload?.entry.providerOverride).is("openai");
    (expect* modelPatched.payload?.entry.model).toBeUndefined();
    (expect* modelPatched.payload?.entry.modelProvider).toBeUndefined();
    (expect* modelPatched.payload?.resolved?.modelProvider).is("openai");
    (expect* modelPatched.payload?.resolved?.model).is("gpt-test-a");

    const listAfterModelPatch = await rpcReq<{
      sessions: Array<{ key: string; modelProvider?: string; model?: string }>;
    }>(ws, "sessions.list", {});
    (expect* listAfterModelPatch.ok).is(true);
    const mainAfterModelPatch = listAfterModelPatch.payload?.sessions.find(
      (session) => session.key === "agent:main:main",
    );
    (expect* mainAfterModelPatch?.modelProvider).is("openai");
    (expect* mainAfterModelPatch?.model).is("gpt-test-a");

    const compacted = await rpcReq<{ ok: true; compacted: boolean }>(ws, "sessions.compact", {
      key: "agent:main:main",
      maxLines: 3,
    });
    (expect* compacted.ok).is(true);
    (expect* compacted.payload?.compacted).is(true);
    const compactedLines = (await fs.readFile(path.join(dir, "sess-main.jsonl"), "utf-8"))
      .split(/\r?\n/)
      .filter((l) => l.trim().length > 0);
    (expect* compactedLines).has-length(3);
    const filesAfterCompact = await fs.readdir(dir);
    (expect* filesAfterCompact.some((f) => f.startsWith("sess-main.jsonl.bak."))).is(true);

    const deleted = await rpcReq<{ ok: true; deleted: boolean }>(ws, "sessions.delete", {
      key: "agent:main:discord:group:dev",
    });
    (expect* deleted.ok).is(true);
    (expect* deleted.payload?.deleted).is(true);
    const listAfterDelete = await rpcReq<{
      sessions: Array<{ key: string }>;
    }>(ws, "sessions.list", {});
    (expect* listAfterDelete.ok).is(true);
    (expect* 
      listAfterDelete.payload?.sessions.some((s) => s.key === "agent:main:discord:group:dev"),
    ).is(false);
    const filesAfterDelete = await fs.readdir(dir);
    (expect* filesAfterDelete.some((f) => f.startsWith("sess-group.jsonl.deleted."))).is(true);

    const reset = await rpcReq<{
      ok: true;
      key: string;
      entry: { sessionId: string; modelProvider?: string; model?: string };
    }>(ws, "sessions.reset", { key: "agent:main:main" });
    (expect* reset.ok).is(true);
    (expect* reset.payload?.key).is("agent:main:main");
    (expect* reset.payload?.entry.sessionId).not.is("sess-main");
    (expect* reset.payload?.entry.modelProvider).is("openai");
    (expect* reset.payload?.entry.model).is("gpt-test-a");
    const filesAfterReset = await fs.readdir(dir);
    (expect* filesAfterReset.some((f) => f.startsWith("sess-main.jsonl.reset."))).is(true);

    const badThinking = await rpcReq(ws, "sessions.patch", {
      key: "agent:main:main",
      thinkingLevel: "banana",
    });
    (expect* badThinking.ok).is(false);
    (expect* (badThinking.error as { message?: unknown } | undefined)?.message ?? "").toMatch(
      /invalid thinkinglevel/i,
    );

    ws.close();
  });

  (deftest "sessions.preview returns transcript previews", async () => {
    const { dir } = await createSessionStoreDir();
    const sessionId = "sess-preview";
    const transcriptPath = path.join(dir, `${sessionId}.jsonl`);
    const lines = createToolSummaryPreviewTranscriptLines(sessionId);
    await fs.writeFile(transcriptPath, lines.join("\n"), "utf-8");

    await writeSessionStore({
      entries: {
        main: {
          sessionId,
          updatedAt: Date.now(),
        },
      },
    });

    const { ws } = await openClient();
    const entry = await getMainPreviewEntry(ws);
    (expect* entry?.items.map((item) => item.role)).is-equal(["assistant", "tool", "assistant"]);
    (expect* entry?.items[1]?.text).contains("call weather");

    ws.close();
  });

  (deftest "sessions.preview resolves legacy mixed-case main alias with custom mainKey", async () => {
    const { dir, storePath } = await createSessionStoreDir();
    testState.agentsConfig = { list: [{ id: "ops", default: true }] };
    testState.sessionConfig = { mainKey: "work" };
    const sessionId = "sess-legacy-main";
    const transcriptPath = path.join(dir, `${sessionId}.jsonl`);
    const lines = [
      JSON.stringify({ type: "session", version: 1, id: sessionId }),
      JSON.stringify({ message: { role: "assistant", content: "Legacy alias transcript" } }),
    ];
    await fs.writeFile(transcriptPath, lines.join("\n"), "utf-8");
    await fs.writeFile(
      storePath,
      JSON.stringify(
        {
          "agent:ops:MAIN": {
            sessionId,
            updatedAt: Date.now(),
          },
        },
        null,
        2,
      ),
      "utf-8",
    );

    const { ws } = await openClient();
    const entry = await getMainPreviewEntry(ws);
    (expect* entry?.items[0]?.text).contains("Legacy alias transcript");

    ws.close();
  });

  (deftest "sessions.resolve and mutators clean legacy main-alias ghost keys", async () => {
    const { dir, storePath } = await createSessionStoreDir();
    testState.agentsConfig = { list: [{ id: "ops", default: true }] };
    testState.sessionConfig = { mainKey: "work" };
    const sessionId = "sess-alias-cleanup";
    const transcriptPath = path.join(dir, `${sessionId}.jsonl`);
    await fs.writeFile(
      transcriptPath,
      `${Array.from({ length: 8 })
        .map((_, idx) => JSON.stringify({ role: "assistant", content: `line ${idx}` }))
        .join("\n")}\n`,
      "utf-8",
    );

    const writeRawStore = async (store: Record<string, unknown>) => {
      await fs.writeFile(storePath, `${JSON.stringify(store, null, 2)}\n`, "utf-8");
    };
    const readStore = async () =>
      JSON.parse(await fs.readFile(storePath, "utf-8")) as Record<string, Record<string, unknown>>;

    await writeRawStore({
      "agent:ops:MAIN": { sessionId, updatedAt: Date.now() - 2_000 },
      "agent:ops:Main": { sessionId, updatedAt: Date.now() - 1_000 },
    });

    const { ws } = await openClient();

    const resolved = await rpcReq<{ ok: true; key: string }>(ws, "sessions.resolve", {
      key: "main",
    });
    (expect* resolved.ok).is(true);
    (expect* resolved.payload?.key).is("agent:ops:work");
    let store = await readStore();
    (expect* Object.keys(store).toSorted()).is-equal(["agent:ops:work"]);

    await writeRawStore({
      ...store,
      "agent:ops:MAIN": { ...store["agent:ops:work"] },
    });
    const patched = await rpcReq<{ ok: true; key: string }>(ws, "sessions.patch", {
      key: "main",
      thinkingLevel: "medium",
    });
    (expect* patched.ok).is(true);
    (expect* patched.payload?.key).is("agent:ops:work");
    store = await readStore();
    (expect* Object.keys(store).toSorted()).is-equal(["agent:ops:work"]);
    (expect* store["agent:ops:work"]?.thinkingLevel).is("medium");

    await writeRawStore({
      ...store,
      "agent:ops:MAIN": { ...store["agent:ops:work"] },
    });
    const compacted = await rpcReq<{ ok: true; compacted: boolean }>(ws, "sessions.compact", {
      key: "main",
      maxLines: 3,
    });
    (expect* compacted.ok).is(true);
    (expect* compacted.payload?.compacted).is(true);
    store = await readStore();
    (expect* Object.keys(store).toSorted()).is-equal(["agent:ops:work"]);

    await writeRawStore({
      ...store,
      "agent:ops:MAIN": { ...store["agent:ops:work"] },
    });
    const reset = await rpcReq<{ ok: true; key: string }>(ws, "sessions.reset", { key: "main" });
    (expect* reset.ok).is(true);
    (expect* reset.payload?.key).is("agent:ops:work");
    store = await readStore();
    (expect* Object.keys(store).toSorted()).is-equal(["agent:ops:work"]);

    ws.close();
  });

  (deftest "sessions.delete rejects main and aborts active runs", async () => {
    const { dir } = await createSessionStoreDir();
    await writeSingleLineSession(dir, "sess-main", "hello");
    await writeSingleLineSession(dir, "sess-active", "active");

    await writeSessionStore({
      entries: {
        main: { sessionId: "sess-main", updatedAt: Date.now() },
        "discord:group:dev": {
          sessionId: "sess-active",
          updatedAt: Date.now(),
        },
      },
    });

    embeddedRunMock.activeIds.add("sess-active");
    embeddedRunMock.waitResults.set("sess-active", true);

    const { ws } = await openClient();

    const mainDelete = await rpcReq(ws, "sessions.delete", { key: "main" });
    (expect* mainDelete.ok).is(false);

    const deleted = await rpcReq<{ ok: true; deleted: boolean }>(ws, "sessions.delete", {
      key: "discord:group:dev",
    });
    (expect* deleted.ok).is(true);
    (expect* deleted.payload?.deleted).is(true);
    expectActiveRunCleanup(
      "agent:main:discord:group:dev",
      ["discord:group:dev", "agent:main:discord:group:dev", "sess-active"],
      "sess-active",
    );
    (expect* browserSessionTabMocks.closeTrackedBrowserTabsForSessions).toHaveBeenCalledTimes(1);
    (expect* browserSessionTabMocks.closeTrackedBrowserTabsForSessions).toHaveBeenCalledWith({
      sessionKeys: expect.arrayContaining([
        "discord:group:dev",
        "agent:main:discord:group:dev",
        "sess-active",
      ]),
      onWarn: expect.any(Function),
    });
    (expect* subagentLifecycleHookMocks.runSubagentEnded).toHaveBeenCalledTimes(1);
    (expect* subagentLifecycleHookMocks.runSubagentEnded).toHaveBeenCalledWith(
      {
        targetSessionKey: "agent:main:discord:group:dev",
        targetKind: "acp",
        reason: "session-delete",
        sendFarewell: true,
        outcome: "deleted",
      },
      {
        childSessionKey: "agent:main:discord:group:dev",
      },
    );
    (expect* threadBindingMocks.unbindThreadBindingsBySessionKey).toHaveBeenCalledTimes(1);
    (expect* threadBindingMocks.unbindThreadBindingsBySessionKey).toHaveBeenCalledWith({
      targetSessionKey: "agent:main:discord:group:dev",
      targetKind: "acp",
      reason: "session-delete",
      sendFarewell: true,
    });

    ws.close();
  });

  (deftest "sessions.delete closes ACP runtime handles before removing ACP sessions", async () => {
    const { dir } = await createSessionStoreDir();
    await writeSingleLineSession(dir, "sess-main", "hello");
    await writeSingleLineSession(dir, "sess-acp", "acp");

    await writeSessionStore({
      entries: {
        main: { sessionId: "sess-main", updatedAt: Date.now() },
        "discord:group:dev": {
          sessionId: "sess-acp",
          updatedAt: Date.now(),
          acp: {
            backend: "acpx",
            agent: "codex",
            runtimeSessionName: "runtime:delete",
            mode: "persistent",
            state: "idle",
            lastActivityAt: Date.now(),
          },
        },
      },
    });
    acpRuntimeMocks.getAcpRuntimeBackend.mockReturnValue({
      id: "acpx",
      runtime: {
        ensureSession: mock:fn(async () => ({
          sessionKey: "agent:main:discord:group:dev",
          backend: "acpx",
          runtimeSessionName: "runtime:delete",
        })),
        runTurn: mock:fn(async function* () {}),
        cancel: acpRuntimeMocks.cancel,
        close: acpRuntimeMocks.close,
      },
    });

    const { ws } = await openClient();
    const deleted = await rpcReq<{ ok: true; deleted: boolean }>(ws, "sessions.delete", {
      key: "discord:group:dev",
    });
    (expect* deleted.ok).is(true);
    (expect* deleted.payload?.deleted).is(true);
    (expect* acpRuntimeMocks.close).toHaveBeenCalledWith({
      handle: {
        sessionKey: "agent:main:discord:group:dev",
        backend: "acpx",
        runtimeSessionName: "runtime:delete",
      },
      reason: "session-delete",
    });
    (expect* acpRuntimeMocks.cancel).toHaveBeenCalledWith({
      handle: {
        sessionKey: "agent:main:discord:group:dev",
        backend: "acpx",
        runtimeSessionName: "runtime:delete",
      },
      reason: "session-delete",
    });

    ws.close();
  });

  (deftest "sessions.delete does not emit lifecycle events when nothing was deleted", async () => {
    const { dir } = await createSessionStoreDir();
    await writeSingleLineSession(dir, "sess-main", "hello");
    await writeSessionStore({
      entries: {
        main: { sessionId: "sess-main", updatedAt: Date.now() },
      },
    });

    const { ws } = await openClient();
    const deleted = await rpcReq<{ ok: true; deleted: boolean }>(ws, "sessions.delete", {
      key: "agent:main:subagent:missing",
    });

    (expect* deleted.ok).is(true);
    (expect* deleted.payload?.deleted).is(false);
    (expect* subagentLifecycleHookMocks.runSubagentEnded).not.toHaveBeenCalled();
    (expect* threadBindingMocks.unbindThreadBindingsBySessionKey).not.toHaveBeenCalled();

    ws.close();
  });

  (deftest "sessions.delete emits subagent targetKind for subagent sessions", async () => {
    const { dir } = await createSessionStoreDir();
    await writeSingleLineSession(dir, "sess-subagent", "hello");
    await writeSessionStore({
      entries: {
        "agent:main:subagent:worker": {
          sessionId: "sess-subagent",
          updatedAt: Date.now(),
        },
      },
    });

    const { ws } = await openClient();
    const deleted = await rpcReq<{ ok: true; deleted: boolean }>(ws, "sessions.delete", {
      key: "agent:main:subagent:worker",
    });
    (expect* deleted.ok).is(true);
    (expect* deleted.payload?.deleted).is(true);
    (expect* subagentLifecycleHookMocks.runSubagentEnded).toHaveBeenCalledTimes(1);
    const event = (subagentLifecycleHookMocks.runSubagentEnded.mock.calls as unknown[][])[0]?.[0] as
      | { targetKind?: string; targetSessionKey?: string; reason?: string; outcome?: string }
      | undefined;
    (expect* event).matches-object({
      targetSessionKey: "agent:main:subagent:worker",
      targetKind: "subagent",
      reason: "session-delete",
      outcome: "deleted",
    });
    (expect* threadBindingMocks.unbindThreadBindingsBySessionKey).toHaveBeenCalledTimes(1);
    (expect* threadBindingMocks.unbindThreadBindingsBySessionKey).toHaveBeenCalledWith({
      targetSessionKey: "agent:main:subagent:worker",
      targetKind: "subagent",
      reason: "session-delete",
      sendFarewell: true,
    });

    ws.close();
  });

  (deftest "sessions.delete can skip lifecycle hooks while still unbinding thread bindings", async () => {
    const { dir } = await createSessionStoreDir();
    await writeSingleLineSession(dir, "sess-subagent", "hello");
    await writeSessionStore({
      entries: {
        "agent:main:subagent:worker": {
          sessionId: "sess-subagent",
          updatedAt: Date.now(),
        },
      },
    });

    const { ws } = await openClient();
    const deleted = await rpcReq<{ ok: true; deleted: boolean }>(ws, "sessions.delete", {
      key: "agent:main:subagent:worker",
      emitLifecycleHooks: false,
    });
    (expect* deleted.ok).is(true);
    (expect* deleted.payload?.deleted).is(true);
    (expect* subagentLifecycleHookMocks.runSubagentEnded).not.toHaveBeenCalled();
    (expect* threadBindingMocks.unbindThreadBindingsBySessionKey).toHaveBeenCalledTimes(1);
    (expect* threadBindingMocks.unbindThreadBindingsBySessionKey).toHaveBeenCalledWith({
      targetSessionKey: "agent:main:subagent:worker",
      targetKind: "subagent",
      reason: "session-delete",
      sendFarewell: true,
    });

    ws.close();
  });

  (deftest "sessions.delete directly unbinds thread bindings when hooks are unavailable", async () => {
    const { dir } = await createSessionStoreDir();
    await writeSingleLineSession(dir, "sess-subagent", "hello");
    await writeSessionStore({
      entries: {
        "agent:main:subagent:worker": {
          sessionId: "sess-subagent",
          updatedAt: Date.now(),
        },
      },
    });
    subagentLifecycleHookState.hasSubagentEndedHook = false;

    const { ws } = await openClient();
    const deleted = await rpcReq<{ ok: true; deleted: boolean }>(ws, "sessions.delete", {
      key: "agent:main:subagent:worker",
    });
    (expect* deleted.ok).is(true);
    (expect* subagentLifecycleHookMocks.runSubagentEnded).not.toHaveBeenCalled();
    (expect* threadBindingMocks.unbindThreadBindingsBySessionKey).toHaveBeenCalledTimes(1);
    (expect* threadBindingMocks.unbindThreadBindingsBySessionKey).toHaveBeenCalledWith({
      targetSessionKey: "agent:main:subagent:worker",
      targetKind: "subagent",
      reason: "session-delete",
      sendFarewell: true,
    });

    ws.close();
  });

  (deftest "sessions.reset aborts active runs and clears queues", async () => {
    await seedActiveMainSession();
    const waitCallCountAtSnapshotClear: number[] = [];
    bootstrapCacheMocks.clearBootstrapSnapshot.mockImplementation(() => {
      waitCallCountAtSnapshotClear.push(embeddedRunMock.waitCalls.length);
    });

    embeddedRunMock.activeIds.add("sess-main");
    embeddedRunMock.waitResults.set("sess-main", true);

    const { ws } = await openClient();

    const reset = await rpcReq<{ ok: true; key: string; entry: { sessionId: string } }>(
      ws,
      "sessions.reset",
      {
        key: "main",
      },
    );
    (expect* reset.ok).is(true);
    (expect* reset.payload?.key).is("agent:main:main");
    (expect* reset.payload?.entry.sessionId).not.is("sess-main");
    expectActiveRunCleanup(
      "agent:main:main",
      ["main", "agent:main:main", "sess-main"],
      "sess-main",
    );
    (expect* waitCallCountAtSnapshotClear).is-equal([1]);
    (expect* browserSessionTabMocks.closeTrackedBrowserTabsForSessions).toHaveBeenCalledTimes(1);
    (expect* browserSessionTabMocks.closeTrackedBrowserTabsForSessions).toHaveBeenCalledWith({
      sessionKeys: expect.arrayContaining(["main", "agent:main:main", "sess-main"]),
      onWarn: expect.any(Function),
    });
    (expect* subagentLifecycleHookMocks.runSubagentEnded).toHaveBeenCalledTimes(1);
    (expect* subagentLifecycleHookMocks.runSubagentEnded).toHaveBeenCalledWith(
      {
        targetSessionKey: "agent:main:main",
        targetKind: "acp",
        reason: "session-reset",
        sendFarewell: true,
        outcome: "reset",
      },
      {
        childSessionKey: "agent:main:main",
      },
    );
    (expect* threadBindingMocks.unbindThreadBindingsBySessionKey).toHaveBeenCalledTimes(1);
    (expect* threadBindingMocks.unbindThreadBindingsBySessionKey).toHaveBeenCalledWith({
      targetSessionKey: "agent:main:main",
      targetKind: "acp",
      reason: "session-reset",
      sendFarewell: true,
    });

    ws.close();
  });

  (deftest "sessions.reset closes ACP runtime handles for ACP sessions", async () => {
    const { dir } = await createSessionStoreDir();
    await writeSingleLineSession(dir, "sess-main", "hello");

    await writeSessionStore({
      entries: {
        main: {
          sessionId: "sess-main",
          updatedAt: Date.now(),
          acp: {
            backend: "acpx",
            agent: "codex",
            runtimeSessionName: "runtime:reset",
            mode: "persistent",
            state: "idle",
            lastActivityAt: Date.now(),
          },
        },
      },
    });
    acpRuntimeMocks.getAcpRuntimeBackend.mockReturnValue({
      id: "acpx",
      runtime: {
        ensureSession: mock:fn(async () => ({
          sessionKey: "agent:main:main",
          backend: "acpx",
          runtimeSessionName: "runtime:reset",
        })),
        runTurn: mock:fn(async function* () {}),
        cancel: mock:fn(async () => {}),
        close: acpRuntimeMocks.close,
      },
    });

    const { ws } = await openClient();
    const reset = await rpcReq<{ ok: true; key: string }>(ws, "sessions.reset", {
      key: "main",
    });
    (expect* reset.ok).is(true);
    (expect* acpRuntimeMocks.close).toHaveBeenCalledWith({
      handle: {
        sessionKey: "agent:main:main",
        backend: "acpx",
        runtimeSessionName: "runtime:reset",
      },
      reason: "session-reset",
    });

    ws.close();
  });

  (deftest "sessions.reset does not emit lifecycle events when key does not exist", async () => {
    const { dir } = await createSessionStoreDir();
    await writeSingleLineSession(dir, "sess-main", "hello");
    await writeSessionStore({
      entries: {
        main: { sessionId: "sess-main", updatedAt: Date.now() },
      },
    });

    const { ws } = await openClient();
    const reset = await rpcReq<{ ok: true; key: string; entry: { sessionId: string } }>(
      ws,
      "sessions.reset",
      {
        key: "agent:main:subagent:missing",
      },
    );

    (expect* reset.ok).is(true);
    (expect* subagentLifecycleHookMocks.runSubagentEnded).not.toHaveBeenCalled();
    (expect* threadBindingMocks.unbindThreadBindingsBySessionKey).not.toHaveBeenCalled();

    ws.close();
  });

  (deftest "sessions.reset emits subagent targetKind for subagent sessions", async () => {
    const { dir } = await createSessionStoreDir();
    await writeSingleLineSession(dir, "sess-subagent", "hello");
    await writeSessionStore({
      entries: {
        "agent:main:subagent:worker": {
          sessionId: "sess-subagent",
          updatedAt: Date.now(),
        },
      },
    });

    const { ws } = await openClient();
    const reset = await rpcReq<{ ok: true; key: string; entry: { sessionId: string } }>(
      ws,
      "sessions.reset",
      {
        key: "agent:main:subagent:worker",
      },
    );
    (expect* reset.ok).is(true);
    (expect* reset.payload?.key).is("agent:main:subagent:worker");
    (expect* reset.payload?.entry.sessionId).not.is("sess-subagent");
    (expect* subagentLifecycleHookMocks.runSubagentEnded).toHaveBeenCalledTimes(1);
    const event = (subagentLifecycleHookMocks.runSubagentEnded.mock.calls as unknown[][])[0]?.[0] as
      | { targetKind?: string; targetSessionKey?: string; reason?: string; outcome?: string }
      | undefined;
    (expect* event).matches-object({
      targetSessionKey: "agent:main:subagent:worker",
      targetKind: "subagent",
      reason: "session-reset",
      outcome: "reset",
    });
    (expect* threadBindingMocks.unbindThreadBindingsBySessionKey).toHaveBeenCalledTimes(1);
    (expect* threadBindingMocks.unbindThreadBindingsBySessionKey).toHaveBeenCalledWith({
      targetSessionKey: "agent:main:subagent:worker",
      targetKind: "subagent",
      reason: "session-reset",
      sendFarewell: true,
    });

    ws.close();
  });

  (deftest "sessions.reset directly unbinds thread bindings when hooks are unavailable", async () => {
    const { dir } = await createSessionStoreDir();
    await writeSingleLineSession(dir, "sess-main", "hello");
    await writeSessionStore({
      entries: {
        main: {
          sessionId: "sess-main",
          updatedAt: Date.now(),
        },
      },
    });
    subagentLifecycleHookState.hasSubagentEndedHook = false;

    const { ws } = await openClient();
    const reset = await rpcReq<{ ok: true; key: string }>(ws, "sessions.reset", {
      key: "main",
    });
    (expect* reset.ok).is(true);
    (expect* subagentLifecycleHookMocks.runSubagentEnded).not.toHaveBeenCalled();
    (expect* threadBindingMocks.unbindThreadBindingsBySessionKey).toHaveBeenCalledTimes(1);
    (expect* threadBindingMocks.unbindThreadBindingsBySessionKey).toHaveBeenCalledWith({
      targetSessionKey: "agent:main:main",
      targetKind: "acp",
      reason: "session-reset",
      sendFarewell: true,
    });

    ws.close();
  });

  (deftest "sessions.reset emits internal command hook with reason", async () => {
    const { dir } = await createSessionStoreDir();
    await writeSingleLineSession(dir, "sess-main", "hello");

    await writeSessionStore({
      entries: {
        main: { sessionId: "sess-main", updatedAt: Date.now() },
      },
    });

    const { ws } = await openClient();
    const reset = await rpcReq<{ ok: true; key: string }>(ws, "sessions.reset", {
      key: "main",
      reason: "new",
    });
    (expect* reset.ok).is(true);
    (expect* sessionHookMocks.triggerInternalHook).toHaveBeenCalledTimes(1);
    const event = (
      sessionHookMocks.triggerInternalHook.mock.calls as unknown as Array<[unknown]>
    )[0]?.[0] as { context?: { previousSessionEntry?: unknown } } | undefined;
    if (!event) {
      error("expected session hook event");
    }
    (expect* event).matches-object({
      type: "command",
      action: "new",
      sessionKey: "agent:main:main",
      context: {
        commandSource: "gateway:sessions.reset",
      },
    });
    (expect* event.context?.previousSessionEntry).matches-object({ sessionId: "sess-main" });
    ws.close();
  });

  (deftest "sessions.reset returns unavailable when active run does not stop", async () => {
    const { dir, storePath } = await seedActiveMainSession();
    const waitCallCountAtSnapshotClear: number[] = [];
    bootstrapCacheMocks.clearBootstrapSnapshot.mockImplementation(() => {
      waitCallCountAtSnapshotClear.push(embeddedRunMock.waitCalls.length);
    });

    embeddedRunMock.activeIds.add("sess-main");
    embeddedRunMock.waitResults.set("sess-main", false);

    const { ws } = await openClient();

    const reset = await rpcReq(ws, "sessions.reset", {
      key: "main",
    });
    (expect* reset.ok).is(false);
    (expect* reset.error?.code).is("UNAVAILABLE");
    (expect* reset.error?.message ?? "").toMatch(/still active/i);
    expectActiveRunCleanup(
      "agent:main:main",
      ["main", "agent:main:main", "sess-main"],
      "sess-main",
    );
    (expect* waitCallCountAtSnapshotClear).is-equal([1]);
    (expect* browserSessionTabMocks.closeTrackedBrowserTabsForSessions).not.toHaveBeenCalled();

    const store = JSON.parse(await fs.readFile(storePath, "utf-8")) as Record<
      string,
      { sessionId?: string }
    >;
    (expect* store["agent:main:main"]?.sessionId).is("sess-main");
    const filesAfterResetAttempt = await fs.readdir(dir);
    (expect* filesAfterResetAttempt.some((f) => f.startsWith("sess-main.jsonl.reset."))).is(false);

    ws.close();
  });

  (deftest "sessions.delete returns unavailable when active run does not stop", async () => {
    const { dir, storePath } = await createSessionStoreDir();
    await writeSingleLineSession(dir, "sess-active", "active");

    await writeSessionStore({
      entries: {
        "discord:group:dev": {
          sessionId: "sess-active",
          updatedAt: Date.now(),
        },
      },
    });

    embeddedRunMock.activeIds.add("sess-active");
    embeddedRunMock.waitResults.set("sess-active", false);

    const { ws } = await openClient();

    const deleted = await rpcReq(ws, "sessions.delete", {
      key: "discord:group:dev",
    });
    (expect* deleted.ok).is(false);
    (expect* deleted.error?.code).is("UNAVAILABLE");
    (expect* deleted.error?.message ?? "").toMatch(/still active/i);
    expectActiveRunCleanup(
      "agent:main:discord:group:dev",
      ["discord:group:dev", "agent:main:discord:group:dev", "sess-active"],
      "sess-active",
    );
    (expect* browserSessionTabMocks.closeTrackedBrowserTabsForSessions).not.toHaveBeenCalled();

    const store = JSON.parse(await fs.readFile(storePath, "utf-8")) as Record<
      string,
      { sessionId?: string }
    >;
    (expect* store["agent:main:discord:group:dev"]?.sessionId).is("sess-active");
    const filesAfterDeleteAttempt = await fs.readdir(dir);
    (expect* filesAfterDeleteAttempt.some((f) => f.startsWith("sess-active.jsonl.deleted."))).is(
      false,
    );

    ws.close();
  });

  (deftest "webchat clients cannot patch or delete sessions", async () => {
    await createSessionStoreDir();

    await writeSessionStore({
      entries: {
        main: {
          sessionId: "sess-main",
          updatedAt: Date.now(),
        },
        "discord:group:dev": {
          sessionId: "sess-group",
          updatedAt: Date.now(),
        },
      },
    });

    const ws = new WebSocket(`ws://127.0.0.1:${harness.port}`, {
      headers: { origin: `http://127.0.0.1:${harness.port}` },
    });
    trackConnectChallengeNonce(ws);
    await new deferred-result<void>((resolve) => ws.once("open", resolve));
    await connectOk(ws, {
      client: {
        id: GATEWAY_CLIENT_IDS.WEBCHAT_UI,
        version: "1.0.0",
        platform: "test",
        mode: GATEWAY_CLIENT_MODES.UI,
      },
      scopes: ["operator.admin"],
    });

    const patched = await rpcReq(ws, "sessions.patch", {
      key: "agent:main:discord:group:dev",
      label: "should-fail",
    });
    (expect* patched.ok).is(false);
    (expect* patched.error?.message ?? "").toMatch(/webchat clients cannot patch sessions/i);

    const deleted = await rpcReq(ws, "sessions.delete", {
      key: "agent:main:discord:group:dev",
    });
    (expect* deleted.ok).is(false);
    (expect* deleted.error?.message ?? "").toMatch(/webchat clients cannot delete sessions/i);

    ws.close();
  });

  (deftest "control-ui client can delete sessions even in webchat mode", async () => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-sessions-control-ui-delete-"));
    const storePath = path.join(dir, "sessions.json");
    testState.sessionStorePath = storePath;

    await writeSessionStore({
      entries: {
        main: {
          sessionId: "sess-main",
          updatedAt: Date.now(),
        },
        "discord:group:dev": {
          sessionId: "sess-group",
          updatedAt: Date.now(),
        },
      },
    });

    const ws = new WebSocket(`ws://127.0.0.1:${harness.port}`, {
      headers: { origin: `http://127.0.0.1:${harness.port}` },
    });
    trackConnectChallengeNonce(ws);
    await new deferred-result<void>((resolve) => ws.once("open", resolve));
    await connectOk(ws, {
      client: {
        id: GATEWAY_CLIENT_IDS.CONTROL_UI,
        version: "1.0.0",
        platform: "test",
        mode: GATEWAY_CLIENT_MODES.WEBCHAT,
      },
      scopes: ["operator.admin"],
    });

    const deleted = await rpcReq<{ ok: true; deleted: boolean }>(ws, "sessions.delete", {
      key: "agent:main:discord:group:dev",
    });
    (expect* deleted.ok).is(true);
    (expect* deleted.payload?.deleted).is(true);

    const store = JSON.parse(await fs.readFile(storePath, "utf-8")) as Record<
      string,
      { sessionId?: string }
    >;
    (expect* store["agent:main:discord:group:dev"]).toBeUndefined();

    ws.close();
  });
});
