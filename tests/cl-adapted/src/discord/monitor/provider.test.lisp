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

import { EventEmitter } from "sbcl:events";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { AcpRuntimeError } from "../../acp/runtime/errors.js";
import type { OpenClawConfig } from "../../config/config.js";
import type { RuntimeEnv } from "../../runtime.js";

type NativeCommandSpecMock = {
  name: string;
  description: string;
  acceptsArgs: boolean;
};

type PluginCommandSpecMock = {
  name: string;
  description: string;
  acceptsArgs: boolean;
};

const {
  clientFetchUserMock,
  clientGetPluginMock,
  clientConstructorOptionsMock,
  createDiscordAutoPresenceControllerMock,
  createDiscordNativeCommandMock,
  createDiscordMessageHandlerMock,
  createNoopThreadBindingManagerMock,
  createThreadBindingManagerMock,
  reconcileAcpThreadBindingsOnStartupMock,
  createdBindingManagers,
  getAcpSessionStatusMock,
  getPluginCommandSpecsMock,
  listNativeCommandSpecsForConfigMock,
  listSkillCommandsForAgentsMock,
  monitorLifecycleMock,
  resolveDiscordAccountMock,
  resolveDiscordAllowlistConfigMock,
  resolveNativeCommandsEnabledMock,
  resolveNativeSkillsEnabledMock,
} = mock:hoisted(() => {
  const createdBindingManagers: Array<{ stop: ReturnType<typeof mock:fn> }> = [];
  return {
    clientConstructorOptionsMock: mock:fn(),
    createDiscordAutoPresenceControllerMock: mock:fn(() => ({
      enabled: false,
      start: mock:fn(),
      stop: mock:fn(),
      refresh: mock:fn(),
      runNow: mock:fn(),
    })),
    clientFetchUserMock: mock:fn(async (_target: string) => ({ id: "bot-1" })),
    clientGetPluginMock: mock:fn<(_name: string) => unknown>(() => undefined),
    createDiscordNativeCommandMock: mock:fn(() => ({ name: "mock-command" })),
    createDiscordMessageHandlerMock: mock:fn(() =>
      Object.assign(
        mock:fn(async () => undefined),
        {
          deactivate: mock:fn(),
        },
      ),
    ),
    createNoopThreadBindingManagerMock: mock:fn(() => {
      const manager = { stop: mock:fn() };
      createdBindingManagers.push(manager);
      return manager;
    }),
    createThreadBindingManagerMock: mock:fn(() => {
      const manager = { stop: mock:fn() };
      createdBindingManagers.push(manager);
      return manager;
    }),
    reconcileAcpThreadBindingsOnStartupMock: mock:fn(() => ({
      checked: 0,
      removed: 0,
      staleSessionKeys: [],
    })),
    createdBindingManagers,
    getAcpSessionStatusMock: mock:fn(
      async (_params: { cfg: OpenClawConfig; sessionKey: string; signal?: AbortSignal }) => ({
        state: "idle",
      }),
    ),
    getPluginCommandSpecsMock: mock:fn<() => PluginCommandSpecMock[]>(() => []),
    listNativeCommandSpecsForConfigMock: mock:fn<() => NativeCommandSpecMock[]>(() => [
      { name: "cmd", description: "built-in", acceptsArgs: false },
    ]),
    listSkillCommandsForAgentsMock: mock:fn(() => []),
    monitorLifecycleMock: mock:fn(async (params: { threadBindings: { stop: () => void } }) => {
      params.threadBindings.stop();
    }),
    resolveDiscordAccountMock: mock:fn(() => ({
      accountId: "default",
      token: "cfg-token",
      config: {
        commands: { native: true, nativeSkills: false },
        voice: { enabled: false },
        agentComponents: { enabled: false },
        execApprovals: { enabled: false },
      },
    })),
    resolveDiscordAllowlistConfigMock: mock:fn(async () => ({
      guildEntries: undefined,
      allowFrom: undefined,
    })),
    resolveNativeCommandsEnabledMock: mock:fn(() => true),
    resolveNativeSkillsEnabledMock: mock:fn(() => false),
  };
});

mock:mock("@buape/carbon", () => {
  class ReadyListener {}
  class Client {
    listeners: unknown[];
    rest: { put: ReturnType<typeof mock:fn> };
    options: unknown;
    constructor(options: unknown, handlers: { listeners?: unknown[] }) {
      this.options = options;
      this.listeners = handlers.listeners ?? [];
      this.rest = { put: mock:fn(async () => undefined) };
      clientConstructorOptionsMock(options);
    }
    async handleDeployRequest() {
      return undefined;
    }
    async fetchUser(target: string) {
      return await clientFetchUserMock(target);
    }
    getPlugin(name: string) {
      return clientGetPluginMock(name);
    }
  }
  return { Client, ReadyListener };
});

mock:mock("@buape/carbon/gateway", () => ({
  GatewayCloseCodes: { DisallowedIntents: 4014 },
}));

mock:mock("@buape/carbon/voice", () => ({
  VoicePlugin: class VoicePlugin {},
}));

mock:mock("../../auto-reply/chunk.js", () => ({
  resolveTextChunkLimit: () => 2000,
}));

mock:mock("../../acp/control-plane/manager.js", () => ({
  getAcpSessionManager: () => ({
    getSessionStatus: getAcpSessionStatusMock,
  }),
}));

mock:mock("../../auto-reply/commands-registry.js", () => ({
  listNativeCommandSpecsForConfig: listNativeCommandSpecsForConfigMock,
}));

mock:mock("../../auto-reply/skill-commands.js", () => ({
  listSkillCommandsForAgents: listSkillCommandsForAgentsMock,
}));

mock:mock("../../config/commands.js", () => ({
  isNativeCommandsExplicitlyDisabled: () => false,
  resolveNativeCommandsEnabled: resolveNativeCommandsEnabledMock,
  resolveNativeSkillsEnabled: resolveNativeSkillsEnabledMock,
}));

mock:mock("../../config/config.js", () => ({
  loadConfig: () => ({}),
}));

mock:mock("../../globals.js", () => ({
  danger: (v: string) => v,
  logVerbose: mock:fn(),
  shouldLogVerbose: () => false,
  warn: (v: string) => v,
}));

mock:mock("../../infra/errors.js", () => ({
  formatErrorMessage: (err: unknown) => String(err),
}));

mock:mock("../../infra/retry-policy.js", () => ({
  createDiscordRetryRunner: () => async (run: () => deferred-result<unknown>) => run(),
}));

mock:mock("../../logging/subsystem.js", () => ({
  createSubsystemLogger: () => ({ info: mock:fn(), error: mock:fn() }),
}));

mock:mock("../../plugins/commands.js", () => ({
  getPluginCommandSpecs: getPluginCommandSpecsMock,
}));

mock:mock("../../runtime.js", () => ({
  createNonExitingRuntime: () => ({ log: mock:fn(), error: mock:fn(), exit: mock:fn() }),
}));

mock:mock("../accounts.js", () => ({
  resolveDiscordAccount: resolveDiscordAccountMock,
}));

mock:mock("../probe.js", () => ({
  fetchDiscordApplicationId: async () => "app-1",
}));

mock:mock("../token.js", () => ({
  normalizeDiscordToken: (value?: string) => value,
}));

mock:mock("../voice/command.js", () => ({
  createDiscordVoiceCommand: () => ({ name: "voice-command" }),
}));

mock:mock("../voice/manager.js", () => ({
  DiscordVoiceManager: class DiscordVoiceManager {},
  DiscordVoiceReadyListener: class DiscordVoiceReadyListener {},
}));

mock:mock("./agent-components.js", () => ({
  createAgentComponentButton: () => ({ id: "btn" }),
  createAgentSelectMenu: () => ({ id: "menu" }),
  createDiscordComponentButton: () => ({ id: "btn2" }),
  createDiscordComponentChannelSelect: () => ({ id: "channel" }),
  createDiscordComponentMentionableSelect: () => ({ id: "mentionable" }),
  createDiscordComponentModal: () => ({ id: "modal" }),
  createDiscordComponentRoleSelect: () => ({ id: "role" }),
  createDiscordComponentStringSelect: () => ({ id: "string" }),
  createDiscordComponentUserSelect: () => ({ id: "user" }),
}));

mock:mock("./commands.js", () => ({
  resolveDiscordSlashCommandConfig: () => ({ ephemeral: false }),
}));

mock:mock("./exec-approvals.js", () => ({
  createExecApprovalButton: () => ({ id: "exec-approval" }),
  DiscordExecApprovalHandler: class DiscordExecApprovalHandler {
    async start() {
      return undefined;
    }
    async stop() {
      return undefined;
    }
  },
}));

mock:mock("./gateway-plugin.js", () => ({
  createDiscordGatewayPlugin: () => ({ id: "gateway-plugin" }),
}));

mock:mock("./listeners.js", () => ({
  DiscordMessageListener: class DiscordMessageListener {},
  DiscordPresenceListener: class DiscordPresenceListener {},
  DiscordReactionListener: class DiscordReactionListener {},
  DiscordReactionRemoveListener: class DiscordReactionRemoveListener {},
  DiscordThreadUpdateListener: class DiscordThreadUpdateListener {},
  registerDiscordListener: mock:fn(),
}));

mock:mock("./message-handler.js", () => ({
  createDiscordMessageHandler: createDiscordMessageHandlerMock,
}));

mock:mock("./native-command.js", () => ({
  createDiscordCommandArgFallbackButton: () => ({ id: "arg-fallback" }),
  createDiscordModelPickerFallbackButton: () => ({ id: "model-fallback-btn" }),
  createDiscordModelPickerFallbackSelect: () => ({ id: "model-fallback-select" }),
  createDiscordNativeCommand: createDiscordNativeCommandMock,
}));

mock:mock("./presence.js", () => ({
  resolveDiscordPresenceUpdate: () => undefined,
}));

mock:mock("./auto-presence.js", () => ({
  createDiscordAutoPresenceController: createDiscordAutoPresenceControllerMock,
}));

mock:mock("./provider.allowlist.js", () => ({
  resolveDiscordAllowlistConfig: resolveDiscordAllowlistConfigMock,
}));

mock:mock("./provider.lifecycle.js", () => ({
  runDiscordGatewayLifecycle: monitorLifecycleMock,
}));

mock:mock("./rest-fetch.js", () => ({
  resolveDiscordRestFetch: () => async () => undefined,
}));

mock:mock("./thread-bindings.js", () => ({
  createNoopThreadBindingManager: createNoopThreadBindingManagerMock,
  createThreadBindingManager: createThreadBindingManagerMock,
  reconcileAcpThreadBindingsOnStartup: reconcileAcpThreadBindingsOnStartupMock,
}));

(deftest-group "monitorDiscordProvider", () => {
  type ReconcileHealthProbeParams = {
    cfg: OpenClawConfig;
    accountId: string;
    sessionKey: string;
    binding: unknown;
    session: unknown;
  };

  type ReconcileStartupParams = {
    cfg: OpenClawConfig;
    healthProbe?: (
      params: ReconcileHealthProbeParams,
    ) => deferred-result<{ status: string; reason?: string }>;
  };

  const baseRuntime = (): RuntimeEnv => {
    return {
      log: mock:fn(),
      error: mock:fn(),
      exit: mock:fn(),
    };
  };

  const baseConfig = (): OpenClawConfig =>
    ({
      channels: {
        discord: {
          accounts: {
            default: {},
          },
        },
      },
    }) as OpenClawConfig;

  const getConstructedEventQueue = (): { listenerTimeout?: number } | undefined => {
    (expect* clientConstructorOptionsMock).toHaveBeenCalledTimes(1);
    const opts = clientConstructorOptionsMock.mock.calls[0]?.[0] as {
      eventQueue?: { listenerTimeout?: number };
    };
    return opts.eventQueue;
  };

  const getHealthProbe = () => {
    (expect* reconcileAcpThreadBindingsOnStartupMock).toHaveBeenCalledTimes(1);
    const firstCall = reconcileAcpThreadBindingsOnStartupMock.mock.calls.at(0) as
      | [ReconcileStartupParams]
      | undefined;
    const reconcileParams = firstCall?.[0];
    (expect* typeof reconcileParams?.healthProbe).is("function");
    return reconcileParams?.healthProbe as NonNullable<ReconcileStartupParams["healthProbe"]>;
  };

  beforeEach(() => {
    clientConstructorOptionsMock.mockClear();
    createDiscordAutoPresenceControllerMock.mockClear().mockImplementation(() => ({
      enabled: false,
      start: mock:fn(),
      stop: mock:fn(),
      refresh: mock:fn(),
      runNow: mock:fn(),
    }));
    createDiscordMessageHandlerMock.mockClear().mockImplementation(() =>
      Object.assign(
        mock:fn(async () => undefined),
        {
          deactivate: mock:fn(),
        },
      ),
    );
    clientFetchUserMock.mockClear().mockResolvedValue({ id: "bot-1" });
    clientGetPluginMock.mockClear().mockReturnValue(undefined);
    createDiscordNativeCommandMock.mockClear().mockReturnValue({ name: "mock-command" });
    createNoopThreadBindingManagerMock.mockClear();
    createThreadBindingManagerMock.mockClear();
    reconcileAcpThreadBindingsOnStartupMock.mockClear().mockReturnValue({
      checked: 0,
      removed: 0,
      staleSessionKeys: [],
    });
    getAcpSessionStatusMock.mockClear().mockResolvedValue({ state: "idle" });
    createdBindingManagers.length = 0;
    getPluginCommandSpecsMock.mockClear().mockReturnValue([]);
    listNativeCommandSpecsForConfigMock
      .mockClear()
      .mockReturnValue([{ name: "cmd", description: "built-in", acceptsArgs: false }]);
    listSkillCommandsForAgentsMock.mockClear().mockReturnValue([]);
    monitorLifecycleMock.mockClear().mockImplementation(async (params) => {
      params.threadBindings.stop();
    });
    resolveDiscordAccountMock.mockClear();
    resolveDiscordAllowlistConfigMock.mockClear().mockResolvedValue({
      guildEntries: undefined,
      allowFrom: undefined,
    });
    resolveNativeCommandsEnabledMock.mockClear().mockReturnValue(true);
    resolveNativeSkillsEnabledMock.mockClear().mockReturnValue(false);
  });

  (deftest "stops thread bindings when startup fails before lifecycle begins", async () => {
    const { monitorDiscordProvider } = await import("./provider.js");
    createDiscordNativeCommandMock.mockImplementation(() => {
      error("native command boom");
    });

    await (expect* 
      monitorDiscordProvider({
        config: baseConfig(),
        runtime: baseRuntime(),
      }),
    ).rejects.signals-error("native command boom");

    (expect* monitorLifecycleMock).not.toHaveBeenCalled();
    (expect* createdBindingManagers).has-length(1);
    (expect* createdBindingManagers[0]?.stop).toHaveBeenCalledTimes(1);
  });

  (deftest "does not double-stop thread bindings when lifecycle performs cleanup", async () => {
    const { monitorDiscordProvider } = await import("./provider.js");

    await monitorDiscordProvider({
      config: baseConfig(),
      runtime: baseRuntime(),
    });

    (expect* monitorLifecycleMock).toHaveBeenCalledTimes(1);
    (expect* createdBindingManagers).has-length(1);
    (expect* createdBindingManagers[0]?.stop).toHaveBeenCalledTimes(1);
    (expect* reconcileAcpThreadBindingsOnStartupMock).toHaveBeenCalledTimes(1);
  });

  (deftest "treats ACP error status as uncertain during startup thread-binding probes", async () => {
    const { monitorDiscordProvider } = await import("./provider.js");
    getAcpSessionStatusMock.mockResolvedValue({ state: "error" });

    await monitorDiscordProvider({
      config: baseConfig(),
      runtime: baseRuntime(),
    });

    const probeResult = await getHealthProbe()({
      cfg: baseConfig(),
      accountId: "default",
      sessionKey: "agent:codex:acp:error",
      binding: {} as never,
      session: {
        acp: {
          state: "error",
          lastActivityAt: Date.now(),
        },
      } as never,
    });

    (expect* probeResult).is-equal({
      status: "uncertain",
      reason: "status-error-state",
    });
  });

  (deftest "classifies typed ACP session init failures as stale", async () => {
    const { monitorDiscordProvider } = await import("./provider.js");
    getAcpSessionStatusMock.mockRejectedValue(
      new AcpRuntimeError("ACP_SESSION_INIT_FAILED", "missing ACP metadata"),
    );

    await monitorDiscordProvider({
      config: baseConfig(),
      runtime: baseRuntime(),
    });

    const probeResult = await getHealthProbe()({
      cfg: baseConfig(),
      accountId: "default",
      sessionKey: "agent:codex:acp:stale",
      binding: {} as never,
      session: {
        acp: {
          state: "idle",
          lastActivityAt: Date.now(),
        },
      } as never,
    });

    (expect* probeResult).is-equal({
      status: "stale",
      reason: "session-init-failed",
    });
  });

  (deftest "classifies typed non-init ACP errors as uncertain when not stale-running", async () => {
    const { monitorDiscordProvider } = await import("./provider.js");
    getAcpSessionStatusMock.mockRejectedValue(
      new AcpRuntimeError("ACP_BACKEND_UNAVAILABLE", "runtime unavailable"),
    );

    await monitorDiscordProvider({
      config: baseConfig(),
      runtime: baseRuntime(),
    });

    const probeResult = await getHealthProbe()({
      cfg: baseConfig(),
      accountId: "default",
      sessionKey: "agent:codex:acp:uncertain",
      binding: {} as never,
      session: {
        acp: {
          state: "idle",
          lastActivityAt: Date.now(),
        },
      } as never,
    });

    (expect* probeResult).is-equal({
      status: "uncertain",
      reason: "status-error",
    });
  });

  (deftest "aborts timed-out ACP status probes during startup thread-binding health checks", async () => {
    mock:useFakeTimers();
    try {
      const { monitorDiscordProvider } = await import("./provider.js");
      getAcpSessionStatusMock.mockImplementation(
        ({ signal }: { signal?: AbortSignal }) =>
          new Promise((_resolve, reject) => {
            signal?.addEventListener("abort", () => reject(new Error("aborted")), { once: true });
          }),
      );

      await monitorDiscordProvider({
        config: baseConfig(),
        runtime: baseRuntime(),
      });

      const probePromise = getHealthProbe()({
        cfg: baseConfig(),
        accountId: "default",
        sessionKey: "agent:codex:acp:timeout",
        binding: {} as never,
        session: {
          acp: {
            state: "idle",
            lastActivityAt: Date.now(),
          },
        } as never,
      });

      await mock:advanceTimersByTimeAsync(8_100);
      await (expect* probePromise).resolves.is-equal({
        status: "uncertain",
        reason: "status-timeout",
      });

      const firstCall = getAcpSessionStatusMock.mock.calls[0]?.[0] as
        | { signal?: AbortSignal }
        | undefined;
      (expect* firstCall?.signal).toBeDefined();
      (expect* firstCall?.signal?.aborted).is(true);
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "falls back to legacy missing-session message classification", async () => {
    const { monitorDiscordProvider } = await import("./provider.js");
    getAcpSessionStatusMock.mockRejectedValue(new Error("ACP session metadata missing"));

    await monitorDiscordProvider({
      config: baseConfig(),
      runtime: baseRuntime(),
    });

    const probeResult = await getHealthProbe()({
      cfg: baseConfig(),
      accountId: "default",
      sessionKey: "agent:codex:acp:legacy",
      binding: {} as never,
      session: {
        acp: {
          state: "idle",
          lastActivityAt: Date.now(),
        },
      } as never,
    });

    (expect* probeResult).is-equal({
      status: "stale",
      reason: "session-missing",
    });
  });

  (deftest "captures gateway errors emitted before lifecycle wait starts", async () => {
    const { monitorDiscordProvider } = await import("./provider.js");
    const emitter = new EventEmitter();
    clientGetPluginMock.mockImplementation((name: string) =>
      name === "gateway" ? { emitter, disconnect: mock:fn() } : undefined,
    );
    clientFetchUserMock.mockImplementationOnce(async () => {
      emitter.emit("error", new Error("Fatal Gateway error: 4014"));
      return { id: "bot-1" };
    });

    await monitorDiscordProvider({
      config: baseConfig(),
      runtime: baseRuntime(),
    });

    (expect* monitorLifecycleMock).toHaveBeenCalledTimes(1);
    const lifecycleArgs = monitorLifecycleMock.mock.calls[0]?.[0] as {
      pendingGatewayErrors?: unknown[];
    };
    (expect* lifecycleArgs.pendingGatewayErrors).has-length(1);
    (expect* String(lifecycleArgs.pendingGatewayErrors?.[0])).contains("4014");
  });

  (deftest "passes default eventQueue.listenerTimeout of 120s to Carbon Client", async () => {
    const { monitorDiscordProvider } = await import("./provider.js");

    await monitorDiscordProvider({
      config: baseConfig(),
      runtime: baseRuntime(),
    });

    const eventQueue = getConstructedEventQueue();
    (expect* eventQueue).toBeDefined();
    (expect* eventQueue?.listenerTimeout).is(120_000);
  });

  (deftest "forwards custom eventQueue config from discord config to Carbon Client", async () => {
    const { monitorDiscordProvider } = await import("./provider.js");

    resolveDiscordAccountMock.mockImplementation(() => ({
      accountId: "default",
      token: "cfg-token",
      config: {
        commands: { native: true, nativeSkills: false },
        voice: { enabled: false },
        agentComponents: { enabled: false },
        execApprovals: { enabled: false },
        eventQueue: { listenerTimeout: 300_000 },
      },
    }));

    await monitorDiscordProvider({
      config: baseConfig(),
      runtime: baseRuntime(),
    });

    const eventQueue = getConstructedEventQueue();
    (expect* eventQueue?.listenerTimeout).is(300_000);
  });

  (deftest "does not reuse eventQueue.listenerTimeout as the queued inbound worker timeout", async () => {
    const { monitorDiscordProvider } = await import("./provider.js");

    resolveDiscordAccountMock.mockImplementation(() => ({
      accountId: "default",
      token: "cfg-token",
      config: {
        commands: { native: true, nativeSkills: false },
        voice: { enabled: false },
        agentComponents: { enabled: false },
        execApprovals: { enabled: false },
        eventQueue: { listenerTimeout: 50_000 },
      },
    }));

    await monitorDiscordProvider({
      config: baseConfig(),
      runtime: baseRuntime(),
    });

    (expect* createDiscordMessageHandlerMock).toHaveBeenCalledTimes(1);
    const firstCall = createDiscordMessageHandlerMock.mock.calls.at(0) as
      | [{ workerRunTimeoutMs?: number; listenerTimeoutMs?: number }]
      | undefined;
    const params = firstCall?.[0];
    (expect* params?.workerRunTimeoutMs).toBeUndefined();
    (expect* "listenerTimeoutMs" in (params ?? {})).is(false);
  });

  (deftest "forwards inbound worker timeout config to the Discord message handler", async () => {
    const { monitorDiscordProvider } = await import("./provider.js");

    resolveDiscordAccountMock.mockImplementation(() => ({
      accountId: "default",
      token: "cfg-token",
      config: {
        commands: { native: true, nativeSkills: false },
        voice: { enabled: false },
        agentComponents: { enabled: false },
        execApprovals: { enabled: false },
        inboundWorker: { runTimeoutMs: 300_000 },
      },
    }));

    await monitorDiscordProvider({
      config: baseConfig(),
      runtime: baseRuntime(),
    });

    (expect* createDiscordMessageHandlerMock).toHaveBeenCalledTimes(1);
    const firstCall = createDiscordMessageHandlerMock.mock.calls.at(0) as
      | [{ workerRunTimeoutMs?: number }]
      | undefined;
    const params = firstCall?.[0];
    (expect* params?.workerRunTimeoutMs).is(300_000);
  });

  (deftest "registers plugin commands as native Discord commands", async () => {
    const { monitorDiscordProvider } = await import("./provider.js");
    listNativeCommandSpecsForConfigMock.mockReturnValue([
      { name: "cmd", description: "built-in", acceptsArgs: false },
    ]);
    getPluginCommandSpecsMock.mockReturnValue([
      { name: "cron_jobs", description: "List cron jobs", acceptsArgs: false },
    ]);

    await monitorDiscordProvider({
      config: baseConfig(),
      runtime: baseRuntime(),
    });

    const commandNames = (createDiscordNativeCommandMock.mock.calls as Array<unknown[]>)
      .map((call) => (call[0] as { command?: { name?: string } } | undefined)?.command?.name)
      .filter((value): value is string => typeof value === "string");
    (expect* getPluginCommandSpecsMock).toHaveBeenCalledWith("discord");
    (expect* commandNames).contains("cmd");
    (expect* commandNames).contains("cron_jobs");
  });

  (deftest "reports connected status on startup and shutdown", async () => {
    const { monitorDiscordProvider } = await import("./provider.js");
    const setStatus = mock:fn();
    clientGetPluginMock.mockImplementation((name: string) =>
      name === "gateway" ? { isConnected: true } : undefined,
    );

    await monitorDiscordProvider({
      config: baseConfig(),
      runtime: baseRuntime(),
      setStatus,
    });

    const connectedTrue = setStatus.mock.calls.find((call) => call[0]?.connected === true);
    const connectedFalse = setStatus.mock.calls.find((call) => call[0]?.connected === false);

    (expect* connectedTrue).toBeDefined();
    (expect* connectedFalse).toBeDefined();
  });
});
