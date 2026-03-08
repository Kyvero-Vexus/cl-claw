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
import { type ChannelId, type ChannelPlugin } from "../channels/plugins/types.js";
import {
  createSubsystemLogger,
  type SubsystemLogger,
  runtimeForLogger,
} from "../logging/subsystem.js";
import { createEmptyPluginRegistry, type PluginRegistry } from "../plugins/registry.js";
import { getActivePluginRegistry, setActivePluginRegistry } from "../plugins/runtime.js";
import type { PluginRuntime } from "../plugins/runtime/types.js";
import { DEFAULT_ACCOUNT_ID } from "../routing/session-key.js";
import type { RuntimeEnv } from "../runtime.js";
import { createChannelManager } from "./server-channels.js";

const hoisted = mock:hoisted(() => {
  const computeBackoff = mock:fn(() => 10);
  const sleepWithAbort = mock:fn((ms: number, abortSignal?: AbortSignal) => {
    return new deferred-result<void>((resolve, reject) => {
      const timer = setTimeout(() => resolve(), ms);
      abortSignal?.addEventListener(
        "abort",
        () => {
          clearTimeout(timer);
          reject(new Error("aborted"));
        },
        { once: true },
      );
    });
  });
  return { computeBackoff, sleepWithAbort };
});

mock:mock("../infra/backoff.js", () => ({
  computeBackoff: hoisted.computeBackoff,
  sleepWithAbort: hoisted.sleepWithAbort,
}));

type TestAccount = {
  enabled?: boolean;
  configured?: boolean;
};

function createTestPlugin(params?: {
  account?: TestAccount;
  startAccount?: NonNullable<ChannelPlugin<TestAccount>["gateway"]>["startAccount"];
  includeDescribeAccount?: boolean;
}): ChannelPlugin<TestAccount> {
  const account = params?.account ?? { enabled: true, configured: true };
  const includeDescribeAccount = params?.includeDescribeAccount !== false;
  const config: ChannelPlugin<TestAccount>["config"] = {
    listAccountIds: () => [DEFAULT_ACCOUNT_ID],
    resolveAccount: () => account,
    isEnabled: (resolved) => resolved.enabled !== false,
  };
  if (includeDescribeAccount) {
    config.describeAccount = (resolved) => ({
      accountId: DEFAULT_ACCOUNT_ID,
      enabled: resolved.enabled !== false,
      configured: resolved.configured !== false,
    });
  }
  const gateway: NonNullable<ChannelPlugin<TestAccount>["gateway"]> = {};
  if (params?.startAccount) {
    gateway.startAccount = params.startAccount;
  }
  return {
    id: "discord",
    meta: {
      id: "discord",
      label: "Discord",
      selectionLabel: "Discord",
      docsPath: "/channels/discord",
      blurb: "test stub",
    },
    capabilities: { chatTypes: ["direct"] },
    config,
    gateway,
  };
}

function installTestRegistry(plugin: ChannelPlugin<TestAccount>) {
  const registry = createEmptyPluginRegistry();
  registry.channels.push({
    pluginId: plugin.id,
    source: "test",
    plugin,
  });
  setActivePluginRegistry(registry);
}

function createManager(options?: { channelRuntime?: PluginRuntime["channel"] }) {
  const log = createSubsystemLogger("gateway/server-channels-test");
  const channelLogs = { discord: log } as Record<ChannelId, SubsystemLogger>;
  const runtime = runtimeForLogger(log);
  const channelRuntimeEnvs = { discord: runtime } as Record<ChannelId, RuntimeEnv>;
  return createChannelManager({
    loadConfig: () => ({}),
    channelLogs,
    channelRuntimeEnvs,
    ...(options?.channelRuntime ? { channelRuntime: options.channelRuntime } : {}),
  });
}

(deftest-group "server-channels auto restart", () => {
  let previousRegistry: PluginRegistry | null = null;

  beforeEach(() => {
    previousRegistry = getActivePluginRegistry();
    mock:useFakeTimers();
    hoisted.computeBackoff.mockClear();
    hoisted.sleepWithAbort.mockClear();
  });

  afterEach(() => {
    mock:useRealTimers();
    setActivePluginRegistry(previousRegistry ?? createEmptyPluginRegistry());
  });

  (deftest "caps crash-loop restarts after max attempts", async () => {
    const startAccount = mock:fn(async () => {});
    installTestRegistry(
      createTestPlugin({
        startAccount,
      }),
    );
    const manager = createManager();

    await manager.startChannels();
    await mock:advanceTimersByTimeAsync(200);

    (expect* startAccount).toHaveBeenCalledTimes(11);
    const snapshot = manager.getRuntimeSnapshot();
    const account = snapshot.channelAccounts.discord?.[DEFAULT_ACCOUNT_ID];
    (expect* account?.running).is(false);
    (expect* account?.reconnectAttempts).is(10);

    await mock:advanceTimersByTimeAsync(200);
    (expect* startAccount).toHaveBeenCalledTimes(11);
  });

  (deftest "does not auto-restart after manual stop during backoff", async () => {
    const startAccount = mock:fn(async () => {});
    installTestRegistry(
      createTestPlugin({
        startAccount,
      }),
    );
    const manager = createManager();

    await manager.startChannels();
    mock:runAllTicks();
    await manager.stopChannel("discord", DEFAULT_ACCOUNT_ID);

    await mock:advanceTimersByTimeAsync(200);
    (expect* startAccount).toHaveBeenCalledTimes(1);
  });

  (deftest "marks enabled/configured when account descriptors omit them", () => {
    installTestRegistry(
      createTestPlugin({
        includeDescribeAccount: false,
      }),
    );
    const manager = createManager();
    const snapshot = manager.getRuntimeSnapshot();
    const account = snapshot.channelAccounts.discord?.[DEFAULT_ACCOUNT_ID];
    (expect* account?.enabled).is(true);
    (expect* account?.configured).is(true);
  });

  (deftest "passes channelRuntime through channel gateway context when provided", async () => {
    const channelRuntime = { marker: "channel-runtime" } as unknown as PluginRuntime["channel"];
    const startAccount = mock:fn(async (ctx) => {
      (expect* ctx.channelRuntime).is(channelRuntime);
    });

    installTestRegistry(createTestPlugin({ startAccount }));
    const manager = createManager({ channelRuntime });

    await manager.startChannels();
    (expect* startAccount).toHaveBeenCalledTimes(1);
  });
});
