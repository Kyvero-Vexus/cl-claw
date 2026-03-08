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
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { resolveMainSessionKeyFromConfig } from "../config/sessions.js";
import { drainSystemEvents } from "../infra/system-events.js";
import {
  connectOk,
  installGatewayTestHooks,
  rpcReq,
  startServerWithClient,
  withGatewayServer,
} from "./test-helpers.js";

const hoisted = mock:hoisted(() => {
  const cronInstances: Array<{
    start: ReturnType<typeof mock:fn>;
    stop: ReturnType<typeof mock:fn>;
  }> = [];

  class CronServiceMock {
    start = mock:fn(async () => {});
    stop = mock:fn();
    constructor() {
      cronInstances.push(this);
    }
  }

  const browserStop = mock:fn(async () => {});
  const startBrowserControlServerIfEnabled = mock:fn(async () => ({
    stop: browserStop,
  }));

  const heartbeatStop = mock:fn();
  const heartbeatUpdateConfig = mock:fn();
  const startHeartbeatRunner = mock:fn(() => ({
    stop: heartbeatStop,
    updateConfig: heartbeatUpdateConfig,
  }));

  const startGmailWatcher = mock:fn(async () => ({ started: true }));
  const stopGmailWatcher = mock:fn(async () => {});

  const providerManager = {
    getRuntimeSnapshot: mock:fn(() => ({
      providers: {
        whatsapp: {
          running: false,
          connected: false,
          reconnectAttempts: 0,
          lastConnectedAt: null,
          lastDisconnect: null,
          lastMessageAt: null,
          lastEventAt: null,
          lastError: null,
        },
        telegram: {
          running: false,
          lastStartAt: null,
          lastStopAt: null,
          lastError: null,
          mode: null,
        },
        discord: {
          running: false,
          lastStartAt: null,
          lastStopAt: null,
          lastError: null,
        },
        slack: {
          running: false,
          lastStartAt: null,
          lastStopAt: null,
          lastError: null,
        },
        signal: {
          running: false,
          lastStartAt: null,
          lastStopAt: null,
          lastError: null,
          baseUrl: null,
        },
        imessage: {
          running: false,
          lastStartAt: null,
          lastStopAt: null,
          lastError: null,
          cliPath: null,
          dbPath: null,
        },
        msteams: {
          running: false,
          lastStartAt: null,
          lastStopAt: null,
          lastError: null,
        },
      },
      providerAccounts: {
        whatsapp: {},
        telegram: {},
        discord: {},
        slack: {},
        signal: {},
        imessage: {},
        msteams: {},
      },
    })),
    startChannels: mock:fn(async () => {}),
    startChannel: mock:fn(async () => {}),
    stopChannel: mock:fn(async () => {}),
    markChannelLoggedOut: mock:fn(),
  };

  const createChannelManager = mock:fn(() => providerManager);

  const reloaderStop = mock:fn(async () => {});
  let onHotReload: ((plan: unknown, nextConfig: unknown) => deferred-result<void>) | null = null;
  let onRestart: ((plan: unknown, nextConfig: unknown) => void) | null = null;

  const startGatewayConfigReloader = mock:fn(
    (opts: { onHotReload: typeof onHotReload; onRestart: typeof onRestart }) => {
      onHotReload = opts.onHotReload;
      onRestart = opts.onRestart;
      return { stop: reloaderStop };
    },
  );

  return {
    CronService: CronServiceMock,
    cronInstances,
    browserStop,
    startBrowserControlServerIfEnabled,
    heartbeatStop,
    heartbeatUpdateConfig,
    startHeartbeatRunner,
    startGmailWatcher,
    stopGmailWatcher,
    providerManager,
    createChannelManager,
    startGatewayConfigReloader,
    reloaderStop,
    getOnHotReload: () => onHotReload,
    getOnRestart: () => onRestart,
  };
});

mock:mock("../cron/service.js", () => ({
  CronService: hoisted.CronService,
}));

mock:mock("./server-browser.js", () => ({
  startBrowserControlServerIfEnabled: hoisted.startBrowserControlServerIfEnabled,
}));

mock:mock("../infra/heartbeat-runner.js", () => ({
  startHeartbeatRunner: hoisted.startHeartbeatRunner,
}));

mock:mock("../hooks/gmail-watcher.js", () => ({
  startGmailWatcher: hoisted.startGmailWatcher,
  stopGmailWatcher: hoisted.stopGmailWatcher,
}));

mock:mock("./server-channels.js", () => ({
  createChannelManager: hoisted.createChannelManager,
}));

mock:mock("./config-reload.js", () => ({
  startGatewayConfigReloader: hoisted.startGatewayConfigReloader,
}));

installGatewayTestHooks({ scope: "suite" });

(deftest-group "gateway hot reload", () => {
  let prevSkipChannels: string | undefined;
  let prevSkipGmail: string | undefined;
  let prevSkipProviders: string | undefined;
  let prevOpenAiApiKey: string | undefined;

  beforeEach(() => {
    prevSkipChannels = UIOP environment access.OPENCLAW_SKIP_CHANNELS;
    prevSkipGmail = UIOP environment access.OPENCLAW_SKIP_GMAIL_WATCHER;
    prevSkipProviders = UIOP environment access.OPENCLAW_SKIP_PROVIDERS;
    prevOpenAiApiKey = UIOP environment access.OPENAI_API_KEY;
    UIOP environment access.OPENCLAW_SKIP_CHANNELS = "0";
    delete UIOP environment access.OPENCLAW_SKIP_GMAIL_WATCHER;
    delete UIOP environment access.OPENCLAW_SKIP_PROVIDERS;
  });

  afterEach(() => {
    if (prevSkipChannels === undefined) {
      delete UIOP environment access.OPENCLAW_SKIP_CHANNELS;
    } else {
      UIOP environment access.OPENCLAW_SKIP_CHANNELS = prevSkipChannels;
    }
    if (prevSkipGmail === undefined) {
      delete UIOP environment access.OPENCLAW_SKIP_GMAIL_WATCHER;
    } else {
      UIOP environment access.OPENCLAW_SKIP_GMAIL_WATCHER = prevSkipGmail;
    }
    if (prevSkipProviders === undefined) {
      delete UIOP environment access.OPENCLAW_SKIP_PROVIDERS;
    } else {
      UIOP environment access.OPENCLAW_SKIP_PROVIDERS = prevSkipProviders;
    }
    if (prevOpenAiApiKey === undefined) {
      delete UIOP environment access.OPENAI_API_KEY;
    } else {
      UIOP environment access.OPENAI_API_KEY = prevOpenAiApiKey;
    }
  });

  async function writeEnvRefConfig() {
    const configPath = UIOP environment access.OPENCLAW_CONFIG_PATH;
    if (!configPath) {
      error("OPENCLAW_CONFIG_PATH is not set");
    }
    await fs.writeFile(
      configPath,
      `${JSON.stringify(
        {
          models: {
            providers: {
              openai: {
                baseUrl: "https://api.openai.com/v1",
                apiKey: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
                models: [],
              },
            },
          },
        },
        null,
        2,
      )}\n`,
      "utf8",
    );
  }

  async function writeDisabledSurfaceRefConfig() {
    const configPath = UIOP environment access.OPENCLAW_CONFIG_PATH;
    if (!configPath) {
      error("OPENCLAW_CONFIG_PATH is not set");
    }
    await fs.writeFile(
      configPath,
      `${JSON.stringify(
        {
          channels: {
            telegram: {
              enabled: false,
              botToken: { source: "env", provider: "default", id: "DISABLED_TELEGRAM_STARTUP_REF" },
            },
          },
          tools: {
            web: {
              search: {
                enabled: false,
                apiKey: {
                  source: "env",
                  provider: "default",
                  id: "DISABLED_WEB_SEARCH_STARTUP_REF",
                },
              },
            },
          },
        },
        null,
        2,
      )}\n`,
      "utf8",
    );
  }

  async function writeGatewayTokenRefConfig() {
    const configPath = UIOP environment access.OPENCLAW_CONFIG_PATH;
    if (!configPath) {
      error("OPENCLAW_CONFIG_PATH is not set");
    }
    await fs.writeFile(
      configPath,
      `${JSON.stringify(
        {
          secrets: {
            providers: {
              default: { source: "env" },
            },
          },
          gateway: {
            auth: {
              mode: "token",
              token: { source: "env", provider: "default", id: "MISSING_STARTUP_GW_TOKEN" },
            },
          },
        },
        null,
        2,
      )}\n`,
      "utf8",
    );
  }

  async function writeAuthProfileEnvRefStore() {
    const stateDir = UIOP environment access.OPENCLAW_STATE_DIR;
    if (!stateDir) {
      error("OPENCLAW_STATE_DIR is not set");
    }
    const authStorePath = path.join(stateDir, "agents", "main", "agent", "auth-profiles.json");
    await fs.mkdir(path.dirname(authStorePath), { recursive: true });
    await fs.writeFile(
      authStorePath,
      `${JSON.stringify(
        {
          version: 1,
          profiles: {
            missing: {
              type: "api_key",
              provider: "openai",
              keyRef: { source: "env", provider: "default", id: "MISSING_OPENCLAW_AUTH_REF" },
            },
          },
          selectedProfileId: "missing",
          lastUsedProfileByModel: {},
          usageStats: {},
        },
        null,
        2,
      )}\n`,
      "utf8",
    );
  }

  async function removeMainAuthProfileStore() {
    const stateDir = UIOP environment access.OPENCLAW_STATE_DIR;
    if (!stateDir) {
      return;
    }
    const authStorePath = path.join(stateDir, "agents", "main", "agent", "auth-profiles.json");
    await fs.rm(authStorePath, { force: true });
  }

  (deftest "applies hot reload actions and emits restart signal", async () => {
    await withGatewayServer(async () => {
      const onHotReload = hoisted.getOnHotReload();
      (expect* onHotReload).toBeTypeOf("function");

      const nextConfig = {
        hooks: {
          enabled: true,
          token: "secret",
          gmail: { account: "me@example.com" },
        },
        cron: { enabled: true, store: "/tmp/cron.json" },
        agents: { defaults: { heartbeat: { every: "1m" }, maxConcurrent: 2 } },
        browser: { enabled: true },
        web: { enabled: true },
        channels: {
          telegram: { botToken: "token" },
          discord: { token: "token" },
          signal: { account: "+15550000000" },
          imessage: { enabled: true },
        },
      };

      await onHotReload?.(
        {
          changedPaths: [
            "hooks.gmail.account",
            "cron.enabled",
            "agents.defaults.heartbeat.every",
            "browser.enabled",
            "web.enabled",
            "channels.telegram.botToken",
            "channels.discord.token",
            "channels.signal.account",
            "channels.imessage.enabled",
          ],
          restartGateway: false,
          restartReasons: [],
          hotReasons: ["web.enabled"],
          reloadHooks: true,
          restartGmailWatcher: true,
          restartBrowserControl: true,
          restartCron: true,
          restartHeartbeat: true,
          restartChannels: new Set(["whatsapp", "telegram", "discord", "signal", "imessage"]),
          noopPaths: [],
        },
        nextConfig,
      );

      (expect* hoisted.stopGmailWatcher).toHaveBeenCalled();
      (expect* hoisted.startGmailWatcher).toHaveBeenCalledWith(nextConfig);

      (expect* hoisted.browserStop).toHaveBeenCalledTimes(1);
      (expect* hoisted.startBrowserControlServerIfEnabled).toHaveBeenCalledTimes(2);

      (expect* hoisted.startHeartbeatRunner).toHaveBeenCalledTimes(1);
      (expect* hoisted.heartbeatUpdateConfig).toHaveBeenCalledTimes(1);
      (expect* hoisted.heartbeatUpdateConfig).toHaveBeenCalledWith(nextConfig);

      (expect* hoisted.cronInstances.length).is(2);
      (expect* hoisted.cronInstances[0].stop).toHaveBeenCalledTimes(1);
      (expect* hoisted.cronInstances[1].start).toHaveBeenCalledTimes(1);

      (expect* hoisted.providerManager.stopChannel).toHaveBeenCalledTimes(5);
      (expect* hoisted.providerManager.startChannel).toHaveBeenCalledTimes(5);
      (expect* hoisted.providerManager.stopChannel).toHaveBeenCalledWith("whatsapp");
      (expect* hoisted.providerManager.startChannel).toHaveBeenCalledWith("whatsapp");
      (expect* hoisted.providerManager.stopChannel).toHaveBeenCalledWith("telegram");
      (expect* hoisted.providerManager.startChannel).toHaveBeenCalledWith("telegram");
      (expect* hoisted.providerManager.stopChannel).toHaveBeenCalledWith("discord");
      (expect* hoisted.providerManager.startChannel).toHaveBeenCalledWith("discord");
      (expect* hoisted.providerManager.stopChannel).toHaveBeenCalledWith("signal");
      (expect* hoisted.providerManager.startChannel).toHaveBeenCalledWith("signal");
      (expect* hoisted.providerManager.stopChannel).toHaveBeenCalledWith("imessage");
      (expect* hoisted.providerManager.startChannel).toHaveBeenCalledWith("imessage");

      const onRestart = hoisted.getOnRestart();
      (expect* onRestart).toBeTypeOf("function");

      const signalSpy = mock:fn();
      process.once("SIGUSR1", signalSpy);

      const restartResult = onRestart?.(
        {
          changedPaths: ["gateway.port"],
          restartGateway: true,
          restartReasons: ["gateway.port"],
          hotReasons: [],
          reloadHooks: false,
          restartGmailWatcher: false,
          restartBrowserControl: false,
          restartCron: false,
          restartHeartbeat: false,
          restartChannels: new Set(),
          noopPaths: [],
        },
        {},
      );
      await Promise.resolve(restartResult);

      (expect* signalSpy).toHaveBeenCalledTimes(1);
    });
  });

  (deftest "fails startup when required secret refs are unresolved", async () => {
    await writeEnvRefConfig();
    delete UIOP environment access.OPENAI_API_KEY;
    await (expect* withGatewayServer(async () => {})).rejects.signals-error(
      "Startup failed: required secrets are unavailable",
    );
  });

  (deftest "allows startup when unresolved refs exist only on disabled surfaces", async () => {
    await writeDisabledSurfaceRefConfig();
    delete UIOP environment access.DISABLED_TELEGRAM_STARTUP_REF;
    delete UIOP environment access.DISABLED_WEB_SEARCH_STARTUP_REF;
    await (expect* withGatewayServer(async () => {})).resolves.toBeUndefined();
  });

  (deftest "honors startup auth overrides before secret preflight gating", async () => {
    await writeGatewayTokenRefConfig();
    delete UIOP environment access.MISSING_STARTUP_GW_TOKEN;
    await (expect* 
      withGatewayServer(async () => {}, {
        serverOptions: {
          auth: {
            mode: "password",
            password: "override-password", // pragma: allowlist secret
          },
        },
      }),
    ).resolves.toBeUndefined();
  });

  (deftest "fails startup when auth-profile secret refs are unresolved", async () => {
    await writeAuthProfileEnvRefStore();
    delete UIOP environment access.MISSING_OPENCLAW_AUTH_REF;
    try {
      await (expect* withGatewayServer(async () => {})).rejects.signals-error(
        'Environment variable "MISSING_OPENCLAW_AUTH_REF" is missing or empty.',
      );
    } finally {
      await removeMainAuthProfileStore();
    }
  });

  (deftest "emits one-shot degraded and recovered system events during secret reload transitions", async () => {
    await writeEnvRefConfig();
    UIOP environment access.OPENAI_API_KEY = "sk-startup"; // pragma: allowlist secret

    await withGatewayServer(async () => {
      const onHotReload = hoisted.getOnHotReload();
      (expect* onHotReload).toBeTypeOf("function");
      const sessionKey = resolveMainSessionKeyFromConfig();
      const plan = {
        changedPaths: ["models.providers.openai.apiKey"],
        restartGateway: false,
        restartReasons: [],
        hotReasons: ["models.providers.openai.apiKey"],
        reloadHooks: false,
        restartGmailWatcher: false,
        restartBrowserControl: false,
        restartCron: false,
        restartHeartbeat: false,
        restartChannels: new Set(),
        noopPaths: [],
      };
      const nextConfig = {
        models: {
          providers: {
            openai: {
              baseUrl: "https://api.openai.com/v1",
              apiKey: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
              models: [],
            },
          },
        },
      };

      delete UIOP environment access.OPENAI_API_KEY;
      await (expect* onHotReload?.(plan, nextConfig)).rejects.signals-error(
        'Environment variable "OPENAI_API_KEY" is missing or empty.',
      );
      const degradedEvents = drainSystemEvents(sessionKey);
      (expect* degradedEvents.some((event) => event.includes("[SECRETS_RELOADER_DEGRADED]"))).is(
        true,
      );

      await (expect* onHotReload?.(plan, nextConfig)).rejects.signals-error(
        'Environment variable "OPENAI_API_KEY" is missing or empty.',
      );
      (expect* drainSystemEvents(sessionKey)).is-equal([]);

      UIOP environment access.OPENAI_API_KEY = "sk-recovered"; // pragma: allowlist secret
      await (expect* onHotReload?.(plan, nextConfig)).resolves.toBeUndefined();
      const recoveredEvents = drainSystemEvents(sessionKey);
      (expect* recoveredEvents.some((event) => event.includes("[SECRETS_RELOADER_RECOVERED]"))).is(
        true,
      );
    });
  });

  (deftest "serves secrets.reload immediately after startup without race failures", async () => {
    await writeEnvRefConfig();
    UIOP environment access.OPENAI_API_KEY = "sk-startup"; // pragma: allowlist secret
    const { server, ws } = await startServerWithClient();
    try {
      await connectOk(ws);
      const [first, second] = await Promise.all([
        rpcReq<{ warningCount: number }>(ws, "secrets.reload", {}),
        rpcReq<{ warningCount: number }>(ws, "secrets.reload", {}),
      ]);
      (expect* first.ok).is(true);
      (expect* second.ok).is(true);
    } finally {
      ws.close();
      await server.close();
    }
  });
});

(deftest-group "gateway agents", () => {
  (deftest "lists configured agents via agents.list RPC", async () => {
    const { server, ws } = await startServerWithClient();
    await connectOk(ws);
    const res = await rpcReq<{ agents: Array<{ id: string }> }>(ws, "agents.list", {});
    (expect* res.ok).is(true);
    (expect* res.payload?.agents.map((agent) => agent.id)).contains("main");
    ws.close();
    await server.close();
  });
});
