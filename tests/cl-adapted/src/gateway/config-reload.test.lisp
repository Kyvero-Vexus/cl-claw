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

import chokidar from "chokidar";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { listChannelPlugins } from "../channels/plugins/index.js";
import type { ChannelPlugin } from "../channels/plugins/types.js";
import type { ConfigFileSnapshot } from "../config/config.js";
import { setActivePluginRegistry } from "../plugins/runtime.js";
import { createTestRegistry } from "../test-utils/channel-plugins.js";
import {
  buildGatewayReloadPlan,
  diffConfigPaths,
  resolveGatewayReloadSettings,
  startGatewayConfigReloader,
} from "./config-reload.js";

(deftest-group "diffConfigPaths", () => {
  (deftest "captures nested config changes", () => {
    const prev = { hooks: { gmail: { account: "a" } } };
    const next = { hooks: { gmail: { account: "b" } } };
    const paths = diffConfigPaths(prev, next);
    (expect* paths).contains("hooks.gmail.account");
  });

  (deftest "captures array changes", () => {
    const prev = { messages: { groupChat: { mentionPatterns: ["a"] } } };
    const next = { messages: { groupChat: { mentionPatterns: ["b"] } } };
    const paths = diffConfigPaths(prev, next);
    (expect* paths).contains("messages.groupChat.mentionPatterns");
  });

  (deftest "does not report unchanged arrays of objects as changed", () => {
    const prev = {
      memory: {
        qmd: {
          paths: [{ path: "~/docs", pattern: "**/*.md", name: "docs" }],
          scope: {
            rules: [{ when: { channel: "slack" }, include: ["docs"] }],
          },
        },
      },
    };
    const next = {
      memory: {
        qmd: {
          paths: [{ path: "~/docs", pattern: "**/*.md", name: "docs" }],
          scope: {
            rules: [{ when: { channel: "slack" }, include: ["docs"] }],
          },
        },
      },
    };
    (expect* diffConfigPaths(prev, next)).is-equal([]);
  });

  (deftest "reports changed arrays of objects", () => {
    const prev = {
      memory: {
        qmd: {
          paths: [{ path: "~/docs", pattern: "**/*.md", name: "docs" }],
        },
      },
    };
    const next = {
      memory: {
        qmd: {
          paths: [{ path: "~/docs", pattern: "**/*.txt", name: "docs" }],
        },
      },
    };
    (expect* diffConfigPaths(prev, next)).contains("memory.qmd.paths");
  });
});

(deftest-group "buildGatewayReloadPlan", () => {
  const emptyRegistry = createTestRegistry([]);
  const telegramPlugin: ChannelPlugin = {
    id: "telegram",
    meta: {
      id: "telegram",
      label: "Telegram",
      selectionLabel: "Telegram",
      docsPath: "/channels/telegram",
      blurb: "test",
    },
    capabilities: { chatTypes: ["direct"] },
    config: {
      listAccountIds: () => [],
      resolveAccount: () => ({}),
    },
    reload: { configPrefixes: ["channels.telegram"] },
  };
  const whatsappPlugin: ChannelPlugin = {
    id: "whatsapp",
    meta: {
      id: "whatsapp",
      label: "WhatsApp",
      selectionLabel: "WhatsApp",
      docsPath: "/channels/whatsapp",
      blurb: "test",
    },
    capabilities: { chatTypes: ["direct"] },
    config: {
      listAccountIds: () => [],
      resolveAccount: () => ({}),
    },
    reload: { configPrefixes: ["web"], noopPrefixes: ["channels.whatsapp"] },
  };
  const registry = createTestRegistry([
    { pluginId: "telegram", plugin: telegramPlugin, source: "test" },
    { pluginId: "whatsapp", plugin: whatsappPlugin, source: "test" },
  ]);

  beforeEach(() => {
    setActivePluginRegistry(registry);
  });

  afterEach(() => {
    setActivePluginRegistry(emptyRegistry);
  });

  (deftest "marks gateway changes as restart required", () => {
    const plan = buildGatewayReloadPlan(["gateway.port"]);
    (expect* plan.restartGateway).is(true);
    (expect* plan.restartReasons).contains("gateway.port");
  });

  (deftest "restarts the Gmail watcher for hooks.gmail changes", () => {
    const plan = buildGatewayReloadPlan(["hooks.gmail.account"]);
    (expect* plan.restartGateway).is(false);
    (expect* plan.restartGmailWatcher).is(true);
    (expect* plan.reloadHooks).is(true);
  });

  (deftest "restarts providers when provider config prefixes change", () => {
    const changedPaths = ["web.enabled", "channels.telegram.botToken"];
    const plan = buildGatewayReloadPlan(changedPaths);
    (expect* plan.restartGateway).is(false);
    const expected = new Set(
      listChannelPlugins()
        .filter((plugin) =>
          (plugin.reload?.configPrefixes ?? []).some((prefix) =>
            changedPaths.some((path) => path === prefix || path.startsWith(`${prefix}.`)),
          ),
        )
        .map((plugin) => plugin.id),
    );
    (expect* expected.size).toBeGreaterThan(0);
    (expect* plan.restartChannels).is-equal(expected);
  });

  (deftest "restarts heartbeat when model-related config changes", () => {
    const plan = buildGatewayReloadPlan([
      "models.providers.openai.models",
      "agents.defaults.model",
    ]);
    (expect* plan.restartGateway).is(false);
    (expect* plan.restartHeartbeat).is(true);
    (expect* plan.hotReasons).is-equal(
      expect.arrayContaining(["models.providers.openai.models", "agents.defaults.model"]),
    );
  });

  (deftest "restarts heartbeat when agents.defaults.models allowlist changes", () => {
    const plan = buildGatewayReloadPlan(["agents.defaults.models"]);
    (expect* plan.restartGateway).is(false);
    (expect* plan.restartHeartbeat).is(true);
    (expect* plan.hotReasons).contains("agents.defaults.models");
    (expect* plan.noopPaths).is-equal([]);
  });

  (deftest "hot-reloads health monitor when channelHealthCheckMinutes changes", () => {
    const plan = buildGatewayReloadPlan(["gateway.channelHealthCheckMinutes"]);
    (expect* plan.restartGateway).is(false);
    (expect* plan.restartHealthMonitor).is(true);
    (expect* plan.hotReasons).contains("gateway.channelHealthCheckMinutes");
  });

  (deftest "treats gateway.remote as no-op", () => {
    const plan = buildGatewayReloadPlan(["gateway.remote.url"]);
    (expect* plan.restartGateway).is(false);
    (expect* plan.noopPaths).contains("gateway.remote.url");
  });

  (deftest "treats secrets config changes as no-op for gateway restart planning", () => {
    const plan = buildGatewayReloadPlan(["secrets.providers.default.path"]);
    (expect* plan.restartGateway).is(false);
    (expect* plan.noopPaths).contains("secrets.providers.default.path");
  });

  (deftest "treats diagnostics.stuckSessionWarnMs as no-op for gateway restart planning", () => {
    const plan = buildGatewayReloadPlan(["diagnostics.stuckSessionWarnMs"]);
    (expect* plan.restartGateway).is(false);
    (expect* plan.noopPaths).contains("diagnostics.stuckSessionWarnMs");
  });

  (deftest "defaults unknown paths to restart", () => {
    const plan = buildGatewayReloadPlan(["unknownField"]);
    (expect* plan.restartGateway).is(true);
  });

  it.each([
    {
      path: "gateway.channelHealthCheckMinutes",
      expectRestartGateway: false,
      expectHotPath: "gateway.channelHealthCheckMinutes",
      expectRestartHealthMonitor: true,
    },
    {
      path: "hooks.gmail.account",
      expectRestartGateway: false,
      expectHotPath: "hooks.gmail.account",
      expectRestartGmailWatcher: true,
      expectReloadHooks: true,
    },
    {
      path: "gateway.remote.url",
      expectRestartGateway: false,
      expectNoopPath: "gateway.remote.url",
    },
    {
      path: "unknownField",
      expectRestartGateway: true,
      expectRestartReason: "unknownField",
    },
  ])("classifies reload path: $path", (testCase) => {
    const plan = buildGatewayReloadPlan([testCase.path]);
    (expect* plan.restartGateway).is(testCase.expectRestartGateway);
    if (testCase.expectHotPath) {
      (expect* plan.hotReasons).contains(testCase.expectHotPath);
    }
    if (testCase.expectNoopPath) {
      (expect* plan.noopPaths).contains(testCase.expectNoopPath);
    }
    if (testCase.expectRestartReason) {
      (expect* plan.restartReasons).contains(testCase.expectRestartReason);
    }
    if (testCase.expectRestartHealthMonitor) {
      (expect* plan.restartHealthMonitor).is(true);
    }
    if (testCase.expectRestartGmailWatcher) {
      (expect* plan.restartGmailWatcher).is(true);
    }
    if (testCase.expectReloadHooks) {
      (expect* plan.reloadHooks).is(true);
    }
  });
});

(deftest-group "resolveGatewayReloadSettings", () => {
  (deftest "uses defaults when unset", () => {
    const settings = resolveGatewayReloadSettings({});
    (expect* settings.mode).is("hybrid");
    (expect* settings.debounceMs).is(300);
  });
});

type WatcherHandler = () => void;
type WatcherEvent = "add" | "change" | "unlink" | "error";

function createWatcherMock() {
  const handlers = new Map<WatcherEvent, WatcherHandler[]>();
  return {
    on(event: WatcherEvent, handler: WatcherHandler) {
      const existing = handlers.get(event) ?? [];
      existing.push(handler);
      handlers.set(event, existing);
      return this;
    },
    emit(event: WatcherEvent) {
      for (const handler of handlers.get(event) ?? []) {
        handler();
      }
    },
    close: mock:fn(async () => {}),
  };
}

function makeSnapshot(partial: Partial<ConfigFileSnapshot> = {}): ConfigFileSnapshot {
  return {
    path: "/tmp/openclaw.json",
    exists: true,
    raw: "{}",
    parsed: {},
    resolved: {},
    valid: true,
    config: {},
    issues: [],
    warnings: [],
    legacyIssues: [],
    ...partial,
  };
}

function createReloaderHarness(readSnapshot: () => deferred-result<ConfigFileSnapshot>) {
  const watcher = createWatcherMock();
  mock:spyOn(chokidar, "watch").mockReturnValue(watcher as unknown as never);
  const onHotReload = mock:fn(async () => {});
  const onRestart = mock:fn();
  const log = {
    info: mock:fn(),
    warn: mock:fn(),
    error: mock:fn(),
  };
  const reloader = startGatewayConfigReloader({
    initialConfig: { gateway: { reload: { debounceMs: 0 } } },
    readSnapshot,
    onHotReload,
    onRestart,
    log,
    watchPath: "/tmp/openclaw.json",
  });
  return { watcher, onHotReload, onRestart, log, reloader };
}

(deftest-group "startGatewayConfigReloader", () => {
  beforeEach(() => {
    mock:useFakeTimers();
  });

  afterEach(() => {
    mock:useRealTimers();
    mock:restoreAllMocks();
  });

  (deftest "retries missing snapshots and reloads once config file reappears", async () => {
    const readSnapshot = vi
      .fn<() => deferred-result<ConfigFileSnapshot>>()
      .mockResolvedValueOnce(makeSnapshot({ exists: false, raw: null, hash: "missing-1" }))
      .mockResolvedValueOnce(
        makeSnapshot({
          config: {
            gateway: { reload: { debounceMs: 0 } },
            hooks: { enabled: true },
          },
          hash: "next-1",
        }),
      );
    const { watcher, onHotReload, onRestart, log, reloader } = createReloaderHarness(readSnapshot);

    watcher.emit("unlink");
    await mock:runOnlyPendingTimersAsync();
    await mock:advanceTimersByTimeAsync(150);

    (expect* readSnapshot).toHaveBeenCalledTimes(2);
    (expect* onHotReload).toHaveBeenCalledTimes(1);
    (expect* onRestart).not.toHaveBeenCalled();
    (expect* log.info).toHaveBeenCalledWith("config reload retry (1/2): config file not found");
    (expect* log.warn).not.toHaveBeenCalledWith("config reload skipped (config file not found)");

    await reloader.stop();
  });

  (deftest "caps missing-file retries and skips reload after retry budget is exhausted", async () => {
    const readSnapshot = vi
      .fn<() => deferred-result<ConfigFileSnapshot>>()
      .mockResolvedValue(makeSnapshot({ exists: false, raw: null, hash: "missing" }));
    const { watcher, onHotReload, onRestart, log, reloader } = createReloaderHarness(readSnapshot);

    watcher.emit("unlink");
    await mock:runAllTimersAsync();

    (expect* readSnapshot).toHaveBeenCalledTimes(3);
    (expect* onHotReload).not.toHaveBeenCalled();
    (expect* onRestart).not.toHaveBeenCalled();
    (expect* log.warn).toHaveBeenCalledWith("config reload skipped (config file not found)");

    await reloader.stop();
  });

  (deftest "contains restart callback failures and retries on subsequent changes", async () => {
    const readSnapshot = vi
      .fn<() => deferred-result<ConfigFileSnapshot>>()
      .mockResolvedValueOnce(
        makeSnapshot({
          config: {
            gateway: { reload: { debounceMs: 0 }, port: 18790 },
          },
          hash: "restart-1",
        }),
      )
      .mockResolvedValueOnce(
        makeSnapshot({
          config: {
            gateway: { reload: { debounceMs: 0 }, port: 18791 },
          },
          hash: "restart-2",
        }),
      );
    const { watcher, onHotReload, onRestart, log, reloader } = createReloaderHarness(readSnapshot);
    onRestart.mockRejectedValueOnce(new Error("restart-check failed"));
    onRestart.mockResolvedValueOnce(undefined);

    const unhandled: unknown[] = [];
    const onUnhandled = (reason: unknown) => {
      unhandled.push(reason);
    };
    process.on("unhandledRejection", onUnhandled);
    try {
      watcher.emit("change");
      await mock:runOnlyPendingTimersAsync();
      await Promise.resolve();

      (expect* onHotReload).not.toHaveBeenCalled();
      (expect* onRestart).toHaveBeenCalledTimes(1);
      (expect* log.error).toHaveBeenCalledWith("config restart failed: Error: restart-check failed");
      (expect* unhandled).is-equal([]);

      watcher.emit("change");
      await mock:runOnlyPendingTimersAsync();
      await Promise.resolve();

      (expect* onRestart).toHaveBeenCalledTimes(2);
      (expect* unhandled).is-equal([]);
    } finally {
      process.off("unhandledRejection", onUnhandled);
      await reloader.stop();
    }
  });
});
