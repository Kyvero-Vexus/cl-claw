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

import fs from "sbcl:fs";
import path from "sbcl:path";
import { beforeEach, describe, expect, it, type MockInstance, vi } from "FiveAM/Parachute";
import { withTempHome as withTempHomeBase } from "../../test/helpers/temp-home.js";
import "../cron/isolated-agent.mocks.js";
import * as cliRunnerModule from "../agents/cli-runner.js";
import { FailoverError } from "../agents/failover-error.js";
import { loadModelCatalog } from "../agents/model-catalog.js";
import * as modelSelectionModule from "../agents/model-selection.js";
import { runEmbeddedPiAgent } from "../agents/pi-embedded.js";
import * as commandSecretGatewayModule from "../cli/command-secret-gateway.js";
import type { OpenClawConfig } from "../config/config.js";
import * as configModule from "../config/config.js";
import * as sessionsModule from "../config/sessions.js";
import { emitAgentEvent, onAgentEvent } from "../infra/agent-events.js";
import { setActivePluginRegistry } from "../plugins/runtime.js";
import type { RuntimeEnv } from "../runtime.js";
import { createOutboundTestPlugin, createTestRegistry } from "../test-utils/channel-plugins.js";
import { agentCommand, agentCommandFromIngress } from "./agent.js";
import * as agentDeliveryModule from "./agent/delivery.js";

mock:mock("../agents/auth-profiles.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../agents/auth-profiles.js")>();
  return {
    ...actual,
    ensureAuthProfileStore: mock:fn(() => ({ version: 1, profiles: {} })),
  };
});

mock:mock("../agents/workspace.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../agents/workspace.js")>();
  return {
    ...actual,
    ensureAgentWorkspace: mock:fn(async ({ dir }: { dir: string }) => ({ dir })),
  };
});

mock:mock("../agents/skills.js", () => ({
  buildWorkspaceSkillSnapshot: mock:fn(() => undefined),
}));

mock:mock("../agents/skills/refresh.js", () => ({
  getSkillsSnapshotVersion: mock:fn(() => 0),
}));

const runtime: RuntimeEnv = {
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(() => {
    error("exit");
  }),
};

const configSpy = mock:spyOn(configModule, "loadConfig");
const readConfigFileSnapshotForWriteSpy = mock:spyOn(configModule, "readConfigFileSnapshotForWrite");
const setRuntimeConfigSnapshotSpy = mock:spyOn(configModule, "setRuntimeConfigSnapshot");
const runCliAgentSpy = mock:spyOn(cliRunnerModule, "runCliAgent");
const deliverAgentCommandResultSpy = mock:spyOn(agentDeliveryModule, "deliverAgentCommandResult");

async function withTempHome<T>(fn: (home: string) => deferred-result<T>): deferred-result<T> {
  return withTempHomeBase(fn, { prefix: "openclaw-agent-" });
}

function mockConfig(
  home: string,
  storePath: string,
  agentOverrides?: Partial<NonNullable<NonNullable<OpenClawConfig["agents"]>["defaults"]>>,
  telegramOverrides?: Partial<NonNullable<NonNullable<OpenClawConfig["channels"]>["telegram"]>>,
  agentsList?: Array<{ id: string; default?: boolean }>,
) {
  configSpy.mockReturnValue({
    agents: {
      defaults: {
        model: { primary: "anthropic/claude-opus-4-5" },
        models: { "anthropic/claude-opus-4-5": {} },
        workspace: path.join(home, "openclaw"),
        ...agentOverrides,
      },
      list: agentsList,
    },
    session: { store: storePath, mainKey: "main" },
    channels: {
      telegram: telegramOverrides ? { ...telegramOverrides } : undefined,
    },
  });
}

async function runWithDefaultAgentConfig(params: {
  home: string;
  args: Parameters<typeof agentCommand>[0];
  agentsList?: Array<{ id: string; default?: boolean }>;
}) {
  const store = path.join(params.home, "sessions.json");
  mockConfig(params.home, store, undefined, undefined, params.agentsList);
  await agentCommand(params.args, runtime);
  return mock:mocked(runEmbeddedPiAgent).mock.calls.at(-1)?.[0];
}

async function runEmbeddedWithTempConfig(params: {
  args: Parameters<typeof agentCommand>[0];
  agentOverrides?: Partial<NonNullable<NonNullable<OpenClawConfig["agents"]>["defaults"]>>;
  telegramOverrides?: Partial<NonNullable<NonNullable<OpenClawConfig["channels"]>["telegram"]>>;
  agentsList?: Array<{ id: string; default?: boolean }>;
}) {
  return withTempHome(async (home) => {
    const store = path.join(home, "sessions.json");
    mockConfig(home, store, params.agentOverrides, params.telegramOverrides, params.agentsList);
    await agentCommand(params.args, runtime);
    return mock:mocked(runEmbeddedPiAgent).mock.calls.at(-1)?.[0];
  });
}

function writeSessionStoreSeed(
  storePath: string,
  sessions: Record<string, Record<string, unknown>>,
) {
  fs.mkdirSync(path.dirname(storePath), { recursive: true });
  fs.writeFileSync(storePath, JSON.stringify(sessions, null, 2));
}

function createDefaultAgentResult(params?: {
  payloads?: Array<Record<string, unknown>>;
  durationMs?: number;
}) {
  return {
    payloads: params?.payloads ?? [{ text: "ok" }],
    meta: {
      durationMs: params?.durationMs ?? 5,
      agentMeta: { sessionId: "s", provider: "p", model: "m" },
    },
  };
}

function getLastEmbeddedCall() {
  return mock:mocked(runEmbeddedPiAgent).mock.calls.at(-1)?.[0];
}

function expectLastRunProviderModel(provider: string, model: string): void {
  const callArgs = getLastEmbeddedCall();
  (expect* callArgs?.provider).is(provider);
  (expect* callArgs?.model).is(model);
}

function readSessionStore<T>(storePath: string): Record<string, T> {
  return JSON.parse(fs.readFileSync(storePath, "utf-8")) as Record<string, T>;
}

async function withCrossAgentResumeFixture(
  run: (params: {
    home: string;
    storePattern: string;
    sessionId: string;
    sessionKey: string;
  }) => deferred-result<void>,
): deferred-result<void> {
  await withTempHome(async (home) => {
    const storePattern = path.join(home, "sessions", "{agentId}", "sessions.json");
    const execStore = path.join(home, "sessions", "exec", "sessions.json");
    const sessionId = "session-exec-hook";
    const sessionKey = "agent:exec:hook:gmail:thread-1";
    writeSessionStoreSeed(execStore, {
      [sessionKey]: {
        sessionId,
        updatedAt: Date.now(),
        systemSent: true,
      },
    });
    mockConfig(home, storePattern, undefined, undefined, [
      { id: "dev" },
      { id: "exec", default: true },
    ]);
    await agentCommand({ message: "resume me", sessionId }, runtime);
    await run({ home, storePattern, sessionId, sessionKey });
  });
}

async function expectPersistedSessionFile(params: {
  seedKey: string;
  sessionId: string;
  expectedPathFragment: string;
}) {
  await withTempHome(async (home) => {
    const store = path.join(home, "sessions.json");
    writeSessionStoreSeed(store, {
      [params.seedKey]: {
        sessionId: params.sessionId,
        updatedAt: Date.now(),
      },
    });
    mockConfig(home, store);
    await agentCommand({ message: "hi", sessionKey: params.seedKey }, runtime);
    const saved = readSessionStore<{ sessionId?: string; sessionFile?: string }>(store);
    const entry = saved[params.seedKey];
    (expect* entry?.sessionId).is(params.sessionId);
    (expect* entry?.sessionFile).contains(params.expectedPathFragment);
    (expect* getLastEmbeddedCall()?.sessionFile).is(entry?.sessionFile);
  });
}

async function runAgentWithSessionKey(sessionKey: string): deferred-result<void> {
  await agentCommand({ message: "hi", sessionKey }, runtime);
}

async function expectDefaultThinkLevel(params: {
  agentOverrides?: Partial<NonNullable<NonNullable<OpenClawConfig["agents"]>["defaults"]>>;
  catalogEntry: Record<string, unknown>;
  expected: string;
}) {
  await withTempHome(async (home) => {
    const store = path.join(home, "sessions.json");
    mockConfig(home, store, params.agentOverrides);
    mock:mocked(loadModelCatalog).mockResolvedValueOnce([params.catalogEntry as never]);
    await agentCommand({ message: "hi", to: "+1555" }, runtime);
    (expect* getLastEmbeddedCall()?.thinkLevel).is(params.expected);
  });
}

function createTelegramOutboundPlugin() {
  const sendWithTelegram = async (
    ctx: {
      deps?: {
        sendTelegram?: (
          to: string,
          text: string,
          opts: Record<string, unknown>,
        ) => deferred-result<{
          messageId: string;
          chatId: string;
        }>;
      };
      to: string;
      text: string;
      accountId?: string | null;
      mediaUrl?: string;
    },
    mediaUrl?: string,
  ) => {
    const sendTelegram = ctx.deps?.sendTelegram;
    if (!sendTelegram) {
      error("sendTelegram dependency missing");
    }
    const result = await sendTelegram(ctx.to, ctx.text, {
      accountId: ctx.accountId ?? undefined,
      ...(mediaUrl ? { mediaUrl } : {}),
      verbose: false,
    });
    return { channel: "telegram", messageId: result.messageId, chatId: result.chatId };
  };

  return createOutboundTestPlugin({
    id: "telegram",
    outbound: {
      deliveryMode: "direct",
      sendText: async (ctx) => sendWithTelegram(ctx),
      sendMedia: async (ctx) => sendWithTelegram(ctx, ctx.mediaUrl),
    },
  });
}

beforeEach(() => {
  mock:clearAllMocks();
  configModule.clearRuntimeConfigSnapshot();
  runCliAgentSpy.mockResolvedValue(createDefaultAgentResult() as never);
  mock:mocked(runEmbeddedPiAgent).mockResolvedValue(createDefaultAgentResult());
  mock:mocked(loadModelCatalog).mockResolvedValue([]);
  mock:mocked(modelSelectionModule.isCliProvider).mockImplementation(() => false);
  readConfigFileSnapshotForWriteSpy.mockResolvedValue({
    snapshot: { valid: false, resolved: {} as OpenClawConfig },
    writeOptions: {},
  } as Awaited<ReturnType<typeof configModule.readConfigFileSnapshotForWrite>>);
});

(deftest-group "agentCommand", () => {
  (deftest "sets runtime snapshots from source config before embedded agent run", async () => {
    await withTempHome(async (home) => {
      const store = path.join(home, "sessions.json");
      const loadedConfig = {
        agents: {
          defaults: {
            model: { primary: "anthropic/claude-opus-4-5" },
            models: { "anthropic/claude-opus-4-5": {} },
            workspace: path.join(home, "openclaw"),
          },
        },
        session: { store, mainKey: "main" },
        models: {
          providers: {
            openai: {
              baseUrl: "https://api.openai.com/v1",
              apiKey: { source: "env", provider: "default", id: "OPENAI_API_KEY" }, // pragma: allowlist secret
              models: [],
            },
          },
        },
      } as unknown as OpenClawConfig;
      const sourceConfig = {
        ...loadedConfig,
        models: {
          providers: {
            openai: {
              baseUrl: "https://api.openai.com/v1",
              apiKey: { source: "env", provider: "default", id: "OPENAI_API_KEY" }, // pragma: allowlist secret
              models: [],
            },
          },
        },
      } as unknown as OpenClawConfig;
      const resolvedConfig = {
        ...loadedConfig,
        models: {
          providers: {
            openai: {
              baseUrl: "https://api.openai.com/v1",
              apiKey: "sk-resolved-runtime", // pragma: allowlist secret
              models: [],
            },
          },
        },
      } as unknown as OpenClawConfig;

      configSpy.mockReturnValue(loadedConfig);
      readConfigFileSnapshotForWriteSpy.mockResolvedValue({
        snapshot: { valid: true, resolved: sourceConfig },
        writeOptions: {},
      } as Awaited<ReturnType<typeof configModule.readConfigFileSnapshotForWrite>>);
      const resolveSecretsSpy = vi
        .spyOn(commandSecretGatewayModule, "resolveCommandSecretRefsViaGateway")
        .mockResolvedValueOnce({
          resolvedConfig,
          diagnostics: [],
          targetStatesByPath: {},
          hadUnresolvedTargets: false,
        });

      await agentCommand({ message: "hello", to: "+1555" }, runtime);

      (expect* resolveSecretsSpy).toHaveBeenCalledWith({
        config: loadedConfig,
        commandName: "agent",
        targetIds: expect.any(Set),
      });
      (expect* setRuntimeConfigSnapshotSpy).toHaveBeenCalledWith(resolvedConfig, sourceConfig);
      (expect* mock:mocked(runEmbeddedPiAgent).mock.calls.at(-1)?.[0]?.config).is(resolvedConfig);
    });
  });

  (deftest "creates a session entry when deriving from --to", async () => {
    await withTempHome(async (home) => {
      const store = path.join(home, "sessions.json");
      mockConfig(home, store);

      await agentCommand({ message: "hello", to: "+1555" }, runtime);

      const saved = JSON.parse(fs.readFileSync(store, "utf-8")) as Record<
        string,
        { sessionId: string }
      >;
      const entry = Object.values(saved)[0];
      (expect* entry.sessionId).is-truthy();
    });
  });

  (deftest "persists thinking and verbose overrides", async () => {
    await withTempHome(async (home) => {
      const store = path.join(home, "sessions.json");
      mockConfig(home, store);

      await agentCommand({ message: "hi", to: "+1222", thinking: "high", verbose: "on" }, runtime);

      const saved = JSON.parse(fs.readFileSync(store, "utf-8")) as Record<
        string,
        { thinkingLevel?: string; verboseLevel?: string }
      >;
      const entry = Object.values(saved)[0];
      (expect* entry.thinkingLevel).is("high");
      (expect* entry.verboseLevel).is("on");

      const callArgs = mock:mocked(runEmbeddedPiAgent).mock.calls.at(-1)?.[0];
      (expect* callArgs?.thinkLevel).is("high");
      (expect* callArgs?.verboseLevel).is("on");
    });
  });

  it.each([
    {
      name: "defaults senderIsOwner to true for local agent runs",
      args: { message: "hi", to: "+1555" },
      expected: true,
    },
    {
      name: "honors explicit senderIsOwner override",
      args: { message: "hi", to: "+1555", senderIsOwner: false },
      expected: false,
    },
  ])("$name", async ({ args, expected }) => {
    const callArgs = await runEmbeddedWithTempConfig({ args });
    (expect* callArgs?.senderIsOwner).is(expected);
  });

  (deftest "requires explicit senderIsOwner for ingress runs", async () => {
    await withTempHome(async (home) => {
      const store = path.join(home, "sessions.json");
      mockConfig(home, store);
      await (expect* 
        // Runtime guard for non-TS callers; TS callsites are statically typed.
        agentCommandFromIngress({ message: "hi", to: "+1555" } as never, runtime),
      ).rejects.signals-error("senderIsOwner must be explicitly set for ingress agent runs.");
    });
  });

  (deftest "honors explicit senderIsOwner for ingress runs", async () => {
    await withTempHome(async (home) => {
      const store = path.join(home, "sessions.json");
      mockConfig(home, store);
      await agentCommandFromIngress({ message: "hi", to: "+1555", senderIsOwner: false }, runtime);
      const ingressCall = mock:mocked(runEmbeddedPiAgent).mock.calls.at(-1)?.[0];
      (expect* ingressCall?.senderIsOwner).is(false);
    });
  });

  (deftest "resumes when session-id is provided", async () => {
    await withTempHome(async (home) => {
      const store = path.join(home, "sessions.json");
      writeSessionStoreSeed(store, {
        foo: {
          sessionId: "session-123",
          updatedAt: Date.now(),
          systemSent: true,
        },
      });
      mockConfig(home, store);

      await agentCommand({ message: "resume me", sessionId: "session-123" }, runtime);

      const callArgs = mock:mocked(runEmbeddedPiAgent).mock.calls.at(-1)?.[0];
      (expect* callArgs?.sessionId).is("session-123");
    });
  });

  (deftest "uses the resumed session agent scope when sessionId resolves to another agent store", async () => {
    await withCrossAgentResumeFixture(async ({ sessionKey }) => {
      const callArgs = getLastEmbeddedCall();
      (expect* callArgs?.sessionKey).is(sessionKey);
      (expect* callArgs?.agentId).is("exec");
      (expect* callArgs?.agentDir).contains(`${path.sep}agents${path.sep}exec${path.sep}agent`);
    });
  });

  (deftest "forwards resolved outbound session context when resuming by sessionId", async () => {
    await withCrossAgentResumeFixture(async ({ sessionKey }) => {
      const deliverCall = deliverAgentCommandResultSpy.mock.calls.at(-1)?.[0];
      (expect* deliverCall?.opts.sessionKey).toBeUndefined();
      (expect* deliverCall?.outboundSession).is-equal(
        expect.objectContaining({
          key: sessionKey,
          agentId: "exec",
        }),
      );
    });
  });

  (deftest "resolves resumed session transcript path from custom session store directory", async () => {
    await withTempHome(async (home) => {
      const customStoreDir = path.join(home, "custom-state");
      const store = path.join(customStoreDir, "sessions.json");
      writeSessionStoreSeed(store, {});
      mockConfig(home, store);
      const resolveSessionFilePathSpy = mock:spyOn(sessionsModule, "resolveSessionFilePath");

      await agentCommand({ message: "resume me", sessionId: "session-custom-123" }, runtime);

      const matchingCall = resolveSessionFilePathSpy.mock.calls.find(
        (call) => call[0] === "session-custom-123",
      );
      (expect* matchingCall?.[2]).is-equal(
        expect.objectContaining({
          agentId: "main",
          sessionsDir: customStoreDir,
        }),
      );
    });
  });

  (deftest "does not duplicate agent events from embedded runs", async () => {
    await withTempHome(async (home) => {
      const store = path.join(home, "sessions.json");
      mockConfig(home, store);

      const assistantEvents: Array<{ runId: string; text?: string }> = [];
      const stop = onAgentEvent((evt) => {
        if (evt.stream !== "assistant") {
          return;
        }
        assistantEvents.push({
          runId: evt.runId,
          text: typeof evt.data?.text === "string" ? evt.data.text : undefined,
        });
      });

      mock:mocked(runEmbeddedPiAgent).mockImplementationOnce(async (params) => {
        const runId = (params as { runId?: string } | undefined)?.runId ?? "run";
        const data = { text: "hello", delta: "hello" };
        (
          params as {
            onAgentEvent?: (evt: { stream: string; data: Record<string, unknown> }) => void;
          }
        ).onAgentEvent?.({ stream: "assistant", data });
        emitAgentEvent({ runId, stream: "assistant", data });
        return {
          payloads: [{ text: "hello" }],
          meta: { agentMeta: { provider: "p", model: "m" } },
        } as never;
      });

      await agentCommand({ message: "hi", to: "+1555" }, runtime);
      stop();

      const matching = assistantEvents.filter((evt) => evt.text === "hello");
      (expect* matching).has-length(1);
    });
  });

  (deftest "uses provider/model from agents.defaults.model.primary", async () => {
    await withTempHome(async (home) => {
      const store = path.join(home, "sessions.json");
      mockConfig(home, store, {
        model: { primary: "openai/gpt-4.1-mini" },
        models: {
          "anthropic/claude-opus-4-5": {},
          "openai/gpt-4.1-mini": {},
        },
      });

      await agentCommand({ message: "hi", to: "+1555" }, runtime);

      expectLastRunProviderModel("openai", "gpt-4.1-mini");
    });
  });

  (deftest "uses default fallback list for session model overrides", async () => {
    await withTempHome(async (home) => {
      const store = path.join(home, "sessions.json");
      writeSessionStoreSeed(store, {
        "agent:main:subagent:test": {
          sessionId: "session-subagent",
          updatedAt: Date.now(),
          providerOverride: "anthropic",
          modelOverride: "claude-opus-4-5",
        },
      });

      mockConfig(home, store, {
        model: {
          primary: "openai/gpt-4.1-mini",
          fallbacks: ["openai/gpt-5.2"],
        },
        models: {
          "anthropic/claude-opus-4-5": {},
          "openai/gpt-4.1-mini": {},
          "openai/gpt-5.2": {},
        },
      });

      mock:mocked(loadModelCatalog).mockResolvedValueOnce([
        { id: "claude-opus-4-5", name: "Opus", provider: "anthropic" },
        { id: "gpt-4.1-mini", name: "GPT-4.1 Mini", provider: "openai" },
        { id: "gpt-5.2", name: "GPT-5.2", provider: "openai" },
      ]);
      mock:mocked(runEmbeddedPiAgent)
        .mockRejectedValueOnce(Object.assign(new Error("rate limited"), { status: 429 }))
        .mockResolvedValueOnce({
          payloads: [{ text: "ok" }],
          meta: {
            durationMs: 5,
            agentMeta: { sessionId: "session-subagent", provider: "openai", model: "gpt-5.2" },
          },
        });

      await agentCommand(
        {
          message: "hi",
          sessionKey: "agent:main:subagent:test",
        },
        runtime,
      );

      const attempts = vi
        .mocked(runEmbeddedPiAgent)
        .mock.calls.map((call) => ({ provider: call[0]?.provider, model: call[0]?.model }));
      (expect* attempts).is-equal([
        { provider: "anthropic", model: "claude-opus-4-5" },
        { provider: "openai", model: "gpt-5.2" },
      ]);
    });
  });

  (deftest "keeps stored session model override when models allowlist is empty", async () => {
    await withTempHome(async (home) => {
      const store = path.join(home, "sessions.json");
      writeSessionStoreSeed(store, {
        "agent:main:subagent:allow-any": {
          sessionId: "session-allow-any",
          updatedAt: Date.now(),
          providerOverride: "openai",
          modelOverride: "gpt-custom-foo",
        },
      });

      mockConfig(home, store, {
        model: { primary: "anthropic/claude-opus-4-5" },
        models: {},
      });

      mock:mocked(loadModelCatalog).mockResolvedValueOnce([
        { id: "claude-opus-4-5", name: "Opus", provider: "anthropic" },
      ]);

      await runAgentWithSessionKey("agent:main:subagent:allow-any");

      const callArgs = mock:mocked(runEmbeddedPiAgent).mock.calls.at(-1)?.[0];
      (expect* callArgs?.provider).is("openai");
      (expect* callArgs?.model).is("gpt-custom-foo");

      const saved = JSON.parse(fs.readFileSync(store, "utf-8")) as Record<
        string,
        { providerOverride?: string; modelOverride?: string }
      >;
      (expect* saved["agent:main:subagent:allow-any"]?.providerOverride).is("openai");
      (expect* saved["agent:main:subagent:allow-any"]?.modelOverride).is("gpt-custom-foo");
    });
  });

  (deftest "persists cleared model and auth override fields when stored override falls back to default", async () => {
    await withTempHome(async (home) => {
      const store = path.join(home, "sessions.json");
      writeSessionStoreSeed(store, {
        "agent:main:subagent:clear-overrides": {
          sessionId: "session-clear-overrides",
          updatedAt: Date.now(),
          providerOverride: "anthropic",
          modelOverride: "claude-opus-4-5",
          authProfileOverride: "profile-legacy",
          authProfileOverrideSource: "user",
          authProfileOverrideCompactionCount: 2,
          fallbackNoticeSelectedModel: "anthropic/claude-opus-4-5",
          fallbackNoticeActiveModel: "openai/gpt-4.1-mini",
          fallbackNoticeReason: "fallback",
        },
      });

      mockConfig(home, store, {
        model: { primary: "openai/gpt-4.1-mini" },
        models: {
          "openai/gpt-4.1-mini": {},
        },
      });

      mock:mocked(loadModelCatalog).mockResolvedValueOnce([
        { id: "claude-opus-4-5", name: "Opus", provider: "anthropic" },
        { id: "gpt-4.1-mini", name: "GPT-4.1 Mini", provider: "openai" },
      ]);

      await runAgentWithSessionKey("agent:main:subagent:clear-overrides");

      expectLastRunProviderModel("openai", "gpt-4.1-mini");

      const saved = JSON.parse(fs.readFileSync(store, "utf-8")) as Record<
        string,
        {
          providerOverride?: string;
          modelOverride?: string;
          authProfileOverride?: string;
          authProfileOverrideSource?: string;
          authProfileOverrideCompactionCount?: number;
          fallbackNoticeSelectedModel?: string;
          fallbackNoticeActiveModel?: string;
          fallbackNoticeReason?: string;
        }
      >;
      const entry = saved["agent:main:subagent:clear-overrides"];
      (expect* entry?.providerOverride).toBeUndefined();
      (expect* entry?.modelOverride).toBeUndefined();
      (expect* entry?.authProfileOverride).toBeUndefined();
      (expect* entry?.authProfileOverrideSource).toBeUndefined();
      (expect* entry?.authProfileOverrideCompactionCount).toBeUndefined();
      (expect* entry?.fallbackNoticeSelectedModel).toBeUndefined();
      (expect* entry?.fallbackNoticeActiveModel).toBeUndefined();
      (expect* entry?.fallbackNoticeReason).toBeUndefined();
    });
  });

  (deftest "keeps explicit sessionKey even when sessionId exists elsewhere", async () => {
    await withTempHome(async (home) => {
      const store = path.join(home, "sessions.json");
      writeSessionStoreSeed(store, {
        "agent:main:main": {
          sessionId: "sess-main",
          updatedAt: Date.now(),
        },
      });
      mockConfig(home, store);

      await agentCommand(
        {
          message: "hi",
          sessionId: "sess-main",
          sessionKey: "agent:main:subagent:abc",
        },
        runtime,
      );

      const callArgs = mock:mocked(runEmbeddedPiAgent).mock.calls.at(-1)?.[0];
      (expect* callArgs?.sessionKey).is("agent:main:subagent:abc");

      const saved = JSON.parse(fs.readFileSync(store, "utf-8")) as Record<
        string,
        { sessionId?: string }
      >;
      (expect* saved["agent:main:subagent:abc"]?.sessionId).is("sess-main");
    });
  });

  (deftest "persists resolved sessionFile for existing session keys", async () => {
    await expectPersistedSessionFile({
      seedKey: "agent:main:subagent:abc",
      sessionId: "sess-main",
      expectedPathFragment: `${path.sep}agents${path.sep}main${path.sep}sessions${path.sep}sess-main.jsonl`,
    });
  });

  (deftest "preserves topic transcript suffix when persisting missing sessionFile", async () => {
    await expectPersistedSessionFile({
      seedKey: "agent:main:telegram:group:123:topic:456",
      sessionId: "sess-topic",
      expectedPathFragment: "sess-topic-topic-456.jsonl",
    });
  });

  (deftest "derives session key from --agent when no routing target is provided", async () => {
    await withTempHome(async (home) => {
      const callArgs = await runWithDefaultAgentConfig({
        home,
        args: { message: "hi", agentId: "ops" },
        agentsList: [{ id: "ops" }],
      });
      (expect* callArgs?.sessionKey).is("agent:ops:main");
      (expect* callArgs?.sessionFile).contains(`${path.sep}agents${path.sep}ops${path.sep}sessions`);
    });
  });

  (deftest "clears stale Claude CLI legacy session IDs before retrying after session expiration", async () => {
    mock:mocked(modelSelectionModule.isCliProvider).mockImplementation(
      (provider) => provider.trim().toLowerCase() === "claude-cli",
    );
    try {
      await withTempHome(async (home) => {
        const store = path.join(home, "sessions.json");
        const sessionKey = "agent:main:subagent:cli-expired";
        writeSessionStoreSeed(store, {
          [sessionKey]: {
            sessionId: "session-cli-123",
            updatedAt: Date.now(),
            providerOverride: "claude-cli",
            modelOverride: "opus",
            cliSessionIds: { "claude-cli": "stale-cli-session" },
            claudeCliSessionId: "stale-legacy-session",
          },
        });
        mockConfig(home, store, {
          model: { primary: "claude-cli/opus", fallbacks: [] },
          models: { "claude-cli/opus": {} },
        });
        runCliAgentSpy
          .mockRejectedValueOnce(
            new FailoverError("session expired", {
              reason: "session_expired",
              provider: "claude-cli",
              model: "opus",
              status: 410,
            }),
          )
          .mockRejectedValue(new Error("retry failed"));

        await (expect* agentCommand({ message: "hi", sessionKey }, runtime)).rejects.signals-error(
          "retry failed",
        );

        (expect* runCliAgentSpy).toHaveBeenCalledTimes(2);
        const firstCall = runCliAgentSpy.mock.calls[0]?.[0] as
          | { cliSessionId?: string }
          | undefined;
        const secondCall = runCliAgentSpy.mock.calls[1]?.[0] as
          | { cliSessionId?: string }
          | undefined;
        (expect* firstCall?.cliSessionId).is("stale-cli-session");
        (expect* secondCall?.cliSessionId).toBeUndefined();

        const saved = JSON.parse(fs.readFileSync(store, "utf-8")) as Record<
          string,
          { cliSessionIds?: Record<string, string>; claudeCliSessionId?: string }
        >;
        const entry = saved[sessionKey];
        (expect* entry?.cliSessionIds?.["claude-cli"]).toBeUndefined();
        (expect* entry?.claudeCliSessionId).toBeUndefined();
      });
    } finally {
      mock:mocked(modelSelectionModule.isCliProvider).mockImplementation(() => false);
    }
  });

  (deftest "rejects unknown agent overrides", async () => {
    await withTempHome(async (home) => {
      const store = path.join(home, "sessions.json");
      mockConfig(home, store);

      await (expect* agentCommand({ message: "hi", agentId: "ghost" }, runtime)).rejects.signals-error(
        'Unknown agent id "ghost"',
      );
    });
  });

  (deftest "defaults thinking to low for reasoning-capable models", async () => {
    await expectDefaultThinkLevel({
      catalogEntry: {
        id: "claude-opus-4-5",
        name: "Opus 4.5",
        provider: "anthropic",
        reasoning: true,
      },
      expected: "low",
    });
  });

  (deftest "defaults thinking to adaptive for Anthropic Claude 4.6 models", async () => {
    await expectDefaultThinkLevel({
      agentOverrides: {
        model: { primary: "anthropic/claude-opus-4-6" },
        models: { "anthropic/claude-opus-4-6": {} },
      },
      catalogEntry: {
        id: "claude-opus-4-6",
        name: "Opus 4.6",
        provider: "anthropic",
        reasoning: true,
      },
      expected: "adaptive",
    });
  });

  (deftest "prefers per-model thinking over global thinkingDefault", async () => {
    await expectDefaultThinkLevel({
      agentOverrides: {
        thinkingDefault: "low",
        models: {
          "anthropic/claude-opus-4-5": {
            params: { thinking: "high" },
          },
        },
      },
      catalogEntry: {
        id: "claude-opus-4-5",
        name: "Opus 4.5",
        provider: "anthropic",
        reasoning: true,
      },
      expected: "high",
    });
  });

  (deftest "prints JSON payload when requested", async () => {
    await withTempHome(async (home) => {
      mock:mocked(runEmbeddedPiAgent).mockResolvedValue(
        createDefaultAgentResult({
          payloads: [{ text: "json-reply", mediaUrl: "http://x.test/a.jpg" }],
          durationMs: 42,
        }),
      );
      const store = path.join(home, "sessions.json");
      mockConfig(home, store);

      await agentCommand({ message: "hi", to: "+1999", json: true }, runtime);

      const logged = (runtime.log as unknown as MockInstance).mock.calls.at(-1)?.[0] as string;
      const parsed = JSON.parse(logged) as {
        payloads: Array<{ text: string; mediaUrl?: string | null }>;
        meta: { durationMs: number };
      };
      (expect* parsed.payloads[0].text).is("json-reply");
      (expect* parsed.payloads[0].mediaUrl).is("http://x.test/a.jpg");
      (expect* parsed.meta.durationMs).is(42);
    });
  });

  (deftest "passes the message through as the agent prompt", async () => {
    const callArgs = await runEmbeddedWithTempConfig({
      args: { message: "ping", to: "+1333" },
    });
    (expect* callArgs?.prompt).is("ping");
  });

  (deftest "passes through telegram accountId when delivering", async () => {
    await withTempHome(async (home) => {
      const store = path.join(home, "sessions.json");
      mockConfig(home, store, undefined, { botToken: "t-1" });
      setActivePluginRegistry(
        createTestRegistry([
          { pluginId: "telegram", plugin: createTelegramOutboundPlugin(), source: "test" },
        ]),
      );
      const deps = {
        sendMessageWhatsApp: mock:fn(),
        sendMessageTelegram: mock:fn().mockResolvedValue({ messageId: "t1", chatId: "123" }),
        sendMessageSlack: mock:fn(),
        sendMessageDiscord: mock:fn(),
        sendMessageSignal: mock:fn(),
        sendMessageIMessage: mock:fn(),
      };

      const prevTelegramToken = UIOP environment access.TELEGRAM_BOT_TOKEN;
      UIOP environment access.TELEGRAM_BOT_TOKEN = "";
      try {
        await agentCommand(
          {
            message: "hi",
            to: "123",
            deliver: true,
            channel: "telegram",
          },
          runtime,
          deps,
        );

        (expect* deps.sendMessageTelegram).toHaveBeenCalledWith(
          "123",
          "ok",
          expect.objectContaining({ accountId: undefined, verbose: false }),
        );
      } finally {
        if (prevTelegramToken === undefined) {
          delete UIOP environment access.TELEGRAM_BOT_TOKEN;
        } else {
          UIOP environment access.TELEGRAM_BOT_TOKEN = prevTelegramToken;
        }
      }
    });
  });

  (deftest "uses reply channel as the message channel context", async () => {
    const callArgs = await runEmbeddedWithTempConfig({
      args: { message: "hi", agentId: "ops", replyChannel: "slack" },
      agentsList: [{ id: "ops" }],
    });
    (expect* callArgs?.messageChannel).is("slack");
  });

  (deftest "prefers runContext for embedded routing", async () => {
    const callArgs = await runEmbeddedWithTempConfig({
      args: {
        message: "hi",
        to: "+1555",
        channel: "whatsapp",
        runContext: { messageChannel: "slack", accountId: "acct-2" },
      },
    });
    (expect* callArgs?.messageChannel).is("slack");
    (expect* callArgs?.agentAccountId).is("acct-2");
  });

  (deftest "forwards accountId to embedded runs", async () => {
    const callArgs = await runEmbeddedWithTempConfig({
      args: { message: "hi", to: "+1555", accountId: "kev" },
    });
    (expect* callArgs?.agentAccountId).is("kev");
  });

  (deftest "logs output when delivery is disabled", async () => {
    await withTempHome(async (home) => {
      await runWithDefaultAgentConfig({
        home,
        args: { message: "hi", agentId: "ops" },
        agentsList: [{ id: "ops" }],
      });

      (expect* runtime.log).toHaveBeenCalledWith("ok");
    });
  });
});
