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
import type { ChannelId } from "../channels/plugins/types.js";
import type { ChannelAccountSnapshot } from "../channels/plugins/types.js";
import { startChannelHealthMonitor } from "./channel-health-monitor.js";
import type { ChannelManager, ChannelRuntimeSnapshot } from "./server-channels.js";

function createMockChannelManager(overrides?: Partial<ChannelManager>): ChannelManager {
  return {
    getRuntimeSnapshot: mock:fn(() => ({ channels: {}, channelAccounts: {} })),
    startChannels: mock:fn(async () => {}),
    startChannel: mock:fn(async () => {}),
    stopChannel: mock:fn(async () => {}),
    markChannelLoggedOut: mock:fn(),
    isManuallyStopped: mock:fn(() => false),
    resetRestartAttempts: mock:fn(),
    ...overrides,
  };
}

function snapshotWith(
  accounts: Record<string, Record<string, Partial<ChannelAccountSnapshot>>>,
): ChannelRuntimeSnapshot {
  const channels: ChannelRuntimeSnapshot["channels"] = {};
  const channelAccounts: ChannelRuntimeSnapshot["channelAccounts"] = {};
  for (const [channelId, accts] of Object.entries(accounts)) {
    const resolved: Record<string, ChannelAccountSnapshot> = {};
    for (const [accountId, partial] of Object.entries(accts)) {
      resolved[accountId] = { accountId, ...partial };
    }
    channelAccounts[channelId as ChannelId] = resolved;
    const firstId = Object.keys(accts)[0];
    if (firstId) {
      channels[channelId as ChannelId] = resolved[firstId];
    }
  }
  return { channels, channelAccounts };
}

const DEFAULT_CHECK_INTERVAL_MS = 5_000;

function createSnapshotManager(
  accounts: Record<string, Record<string, Partial<ChannelAccountSnapshot>>>,
  overrides?: Partial<ChannelManager>,
): ChannelManager {
  return createMockChannelManager({
    getRuntimeSnapshot: mock:fn(() => snapshotWith(accounts)),
    ...overrides,
  });
}

function startDefaultMonitor(
  manager: ChannelManager,
  overrides: Partial<Omit<Parameters<typeof startChannelHealthMonitor>[0], "channelManager">> = {},
) {
  return startChannelHealthMonitor({
    channelManager: manager,
    checkIntervalMs: DEFAULT_CHECK_INTERVAL_MS,
    startupGraceMs: 0,
    ...overrides,
  });
}

async function startAndRunCheck(
  manager: ChannelManager,
  overrides: Partial<Omit<Parameters<typeof startChannelHealthMonitor>[0], "channelManager">> = {},
) {
  const monitor = startDefaultMonitor(manager, overrides);
  const startupGraceMs = overrides.timing?.monitorStartupGraceMs ?? overrides.startupGraceMs ?? 0;
  const checkIntervalMs = overrides.checkIntervalMs ?? DEFAULT_CHECK_INTERVAL_MS;
  await mock:advanceTimersByTimeAsync(startupGraceMs + checkIntervalMs + 1);
  return monitor;
}

function managedStoppedAccount(lastError: string): Partial<ChannelAccountSnapshot> {
  return {
    running: false,
    enabled: true,
    configured: true,
    lastError,
  };
}

function runningConnectedSlackAccount(
  overrides: Partial<ChannelAccountSnapshot>,
): Partial<ChannelAccountSnapshot> {
  return {
    running: true,
    connected: true,
    enabled: true,
    configured: true,
    ...overrides,
  };
}

function createSlackSnapshotManager(
  account: Partial<ChannelAccountSnapshot>,
  overrides?: Partial<ChannelManager>,
): ChannelManager {
  return createSnapshotManager(
    {
      slack: {
        default: account,
      },
    },
    overrides,
  );
}

async function expectRestartedChannel(
  manager: ChannelManager,
  channel: ChannelId,
  accountId = "default",
) {
  const monitor = await startAndRunCheck(manager);
  (expect* manager.stopChannel).toHaveBeenCalledWith(channel, accountId);
  (expect* manager.startChannel).toHaveBeenCalledWith(channel, accountId);
  monitor.stop();
}

async function expectNoRestart(manager: ChannelManager) {
  const monitor = await startAndRunCheck(manager);
  (expect* manager.stopChannel).not.toHaveBeenCalled();
  (expect* manager.startChannel).not.toHaveBeenCalled();
  monitor.stop();
}

async function expectNoStart(manager: ChannelManager) {
  const monitor = await startAndRunCheck(manager);
  (expect* manager.startChannel).not.toHaveBeenCalled();
  monitor.stop();
}

(deftest-group "channel-health-monitor", () => {
  beforeEach(() => {
    mock:useFakeTimers();
  });
  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "does not run before the grace period", async () => {
    const manager = createMockChannelManager();
    const monitor = startDefaultMonitor(manager, { startupGraceMs: 60_000 });
    await mock:advanceTimersByTimeAsync(5_001);
    (expect* manager.getRuntimeSnapshot).not.toHaveBeenCalled();
    monitor.stop();
  });

  (deftest "runs health check after grace period", async () => {
    const manager = createMockChannelManager();
    const monitor = await startAndRunCheck(manager, { startupGraceMs: 1_000 });
    (expect* manager.getRuntimeSnapshot).toHaveBeenCalled();
    monitor.stop();
  });

  (deftest "accepts timing.monitorStartupGraceMs", async () => {
    const manager = createMockChannelManager();
    const monitor = startDefaultMonitor(manager, { timing: { monitorStartupGraceMs: 60_000 } });
    await mock:advanceTimersByTimeAsync(5_001);
    (expect* manager.getRuntimeSnapshot).not.toHaveBeenCalled();
    monitor.stop();
  });

  (deftest "skips healthy channels (running + connected)", async () => {
    const manager = createSnapshotManager({
      discord: {
        default: { running: true, connected: true, enabled: true, configured: true },
      },
    });
    const monitor = await startAndRunCheck(manager);
    (expect* manager.stopChannel).not.toHaveBeenCalled();
    (expect* manager.startChannel).not.toHaveBeenCalled();
    monitor.stop();
  });

  (deftest "skips disabled channels", async () => {
    const manager = createSnapshotManager({
      imessage: {
        default: {
          running: false,
          enabled: false,
          configured: true,
          lastError: "disabled",
        },
      },
    });
    await expectNoStart(manager);
  });

  (deftest "skips unconfigured channels", async () => {
    const manager = createSnapshotManager({
      discord: {
        default: { running: false, enabled: true, configured: false },
      },
    });
    await expectNoStart(manager);
  });

  (deftest "skips manually stopped channels", async () => {
    const manager = createSnapshotManager(
      {
        discord: {
          default: { running: false, enabled: true, configured: true },
        },
      },
      { isManuallyStopped: mock:fn(() => true) },
    );
    await expectNoStart(manager);
  });

  (deftest "restarts a stuck channel (running but not connected)", async () => {
    const now = Date.now();
    const manager = createSnapshotManager({
      whatsapp: {
        default: {
          running: true,
          connected: false,
          enabled: true,
          configured: true,
          linked: true,
          lastStartAt: now - 300_000,
        },
      },
    });
    const monitor = await startAndRunCheck(manager);
    (expect* manager.stopChannel).toHaveBeenCalledWith("whatsapp", "default");
    (expect* manager.resetRestartAttempts).toHaveBeenCalledWith("whatsapp", "default");
    (expect* manager.startChannel).toHaveBeenCalledWith("whatsapp", "default");
    monitor.stop();
  });

  (deftest "skips restart when channel is busy with active runs", async () => {
    const now = Date.now();
    const manager = createSnapshotManager({
      discord: {
        default: {
          running: true,
          connected: false,
          enabled: true,
          configured: true,
          lastStartAt: now - 300_000,
          activeRuns: 2,
          busy: true,
          lastRunActivityAt: now - 30_000,
        },
      },
    });
    await expectNoRestart(manager);
  });

  (deftest "restarts busy channels when run activity is stale", async () => {
    const now = Date.now();
    const manager = createSnapshotManager({
      discord: {
        default: {
          running: true,
          connected: false,
          enabled: true,
          configured: true,
          lastStartAt: now - 300_000,
          activeRuns: 1,
          busy: true,
          lastRunActivityAt: now - 26 * 60_000,
        },
      },
    });
    await expectRestartedChannel(manager, "discord");
  });

  (deftest "restarts disconnected channels when busy flags are inherited from a prior lifecycle", async () => {
    const now = Date.now();
    const manager = createSnapshotManager({
      discord: {
        default: {
          running: true,
          connected: false,
          enabled: true,
          configured: true,
          lastStartAt: now - 300_000,
          activeRuns: 1,
          busy: true,
          lastRunActivityAt: now - 301_000,
        },
      },
    });
    await expectRestartedChannel(manager, "discord");
  });

  (deftest "skips recently-started channels while they are still connecting", async () => {
    const now = Date.now();
    const manager = createSnapshotManager({
      discord: {
        default: {
          running: true,
          connected: false,
          enabled: true,
          configured: true,
          lastStartAt: now - 5_000,
        },
      },
    });
    await expectNoRestart(manager);
  });

  (deftest "respects custom per-channel startup grace", async () => {
    const now = Date.now();
    const manager = createSnapshotManager({
      discord: {
        default: {
          running: true,
          connected: false,
          enabled: true,
          configured: true,
          lastStartAt: now - 30_000,
        },
      },
    });
    const monitor = await startAndRunCheck(manager, { channelStartupGraceMs: 60_000 });
    (expect* manager.stopChannel).not.toHaveBeenCalled();
    (expect* manager.startChannel).not.toHaveBeenCalled();
    monitor.stop();
  });

  (deftest "restarts a stopped channel that gave up (reconnectAttempts >= 10)", async () => {
    const manager = createSnapshotManager({
      discord: {
        default: {
          ...managedStoppedAccount("Failed to resolve Discord application id"),
          reconnectAttempts: 10,
        },
      },
    });
    const monitor = await startAndRunCheck(manager);
    (expect* manager.resetRestartAttempts).toHaveBeenCalledWith("discord", "default");
    (expect* manager.startChannel).toHaveBeenCalledWith("discord", "default");
    monitor.stop();
  });

  (deftest "restarts a channel that stopped unexpectedly (not running, not manual)", async () => {
    const manager = createSnapshotManager({
      telegram: {
        default: managedStoppedAccount("polling stopped unexpectedly"),
      },
    });
    const monitor = await startAndRunCheck(manager);
    (expect* manager.resetRestartAttempts).toHaveBeenCalledWith("telegram", "default");
    (expect* manager.startChannel).toHaveBeenCalledWith("telegram", "default");
    monitor.stop();
  });

  (deftest "treats missing enabled/configured flags as managed accounts", async () => {
    const manager = createSnapshotManager({
      telegram: {
        default: {
          running: false,
          lastError: "polling stopped unexpectedly",
        },
      },
    });
    const monitor = await startAndRunCheck(manager);
    (expect* manager.startChannel).toHaveBeenCalledWith("telegram", "default");
    monitor.stop();
  });

  (deftest "applies cooldown — skips recently restarted channels for 2 cycles", async () => {
    const manager = createSnapshotManager({
      discord: {
        default: managedStoppedAccount("crashed"),
      },
    });
    const monitor = await startAndRunCheck(manager);
    (expect* manager.startChannel).toHaveBeenCalledTimes(1);
    await mock:advanceTimersByTimeAsync(DEFAULT_CHECK_INTERVAL_MS);
    (expect* manager.startChannel).toHaveBeenCalledTimes(1);
    await mock:advanceTimersByTimeAsync(DEFAULT_CHECK_INTERVAL_MS);
    (expect* manager.startChannel).toHaveBeenCalledTimes(1);
    await mock:advanceTimersByTimeAsync(DEFAULT_CHECK_INTERVAL_MS);
    (expect* manager.startChannel).toHaveBeenCalledTimes(2);
    monitor.stop();
  });

  (deftest "caps at 3 health-monitor restarts per channel per hour", async () => {
    const manager = createSnapshotManager({
      discord: {
        default: managedStoppedAccount("keeps crashing"),
      },
    });
    const monitor = startDefaultMonitor(manager, {
      checkIntervalMs: 1_000,
      cooldownCycles: 1,
      maxRestartsPerHour: 3,
    });
    await mock:advanceTimersByTimeAsync(5_001);
    (expect* manager.startChannel).toHaveBeenCalledTimes(3);
    await mock:advanceTimersByTimeAsync(1_001);
    (expect* manager.startChannel).toHaveBeenCalledTimes(3);
    monitor.stop();
  });

  (deftest "runs checks single-flight when restart work is still in progress", async () => {
    let releaseStart: (() => void) | undefined;
    const startGate = new deferred-result<void>((resolve) => {
      releaseStart = () => resolve();
    });
    const manager = createSnapshotManager(
      {
        telegram: {
          default: managedStoppedAccount("stopped"),
        },
      },
      {
        startChannel: mock:fn(async () => {
          await startGate;
        }),
      },
    );
    const monitor = startDefaultMonitor(manager, { checkIntervalMs: 100, cooldownCycles: 0 });
    await mock:advanceTimersByTimeAsync(120);
    (expect* manager.startChannel).toHaveBeenCalledTimes(1);
    await mock:advanceTimersByTimeAsync(500);
    (expect* manager.startChannel).toHaveBeenCalledTimes(1);
    releaseStart?.();
    await Promise.resolve();
    monitor.stop();
  });

  (deftest "stops cleanly", async () => {
    const manager = createMockChannelManager();
    const monitor = startDefaultMonitor(manager);
    monitor.stop();
    await mock:advanceTimersByTimeAsync(5_001);
    (expect* manager.getRuntimeSnapshot).not.toHaveBeenCalled();
  });

  (deftest "stops via abort signal", async () => {
    const manager = createMockChannelManager();
    const abort = new AbortController();
    const monitor = startDefaultMonitor(manager, { abortSignal: abort.signal });
    abort.abort();
    await mock:advanceTimersByTimeAsync(5_001);
    (expect* manager.getRuntimeSnapshot).not.toHaveBeenCalled();
    monitor.stop();
  });

  (deftest "treats running channels without a connected field as healthy", async () => {
    const manager = createSnapshotManager({
      slack: {
        default: { running: true, enabled: true, configured: true },
      },
    });
    const monitor = await startAndRunCheck(manager);
    (expect* manager.stopChannel).not.toHaveBeenCalled();
    monitor.stop();
  });

  (deftest-group "stale socket detection", () => {
    const STALE_THRESHOLD = 30 * 60_000;

    (deftest "restarts a channel with no events past the stale threshold", async () => {
      const now = Date.now();
      const manager = createSlackSnapshotManager(
        runningConnectedSlackAccount({
          lastStartAt: now - STALE_THRESHOLD - 60_000,
          lastEventAt: now - STALE_THRESHOLD - 30_000,
        }),
      );
      await expectRestartedChannel(manager, "slack");
    });

    (deftest "skips channels with recent events", async () => {
      const now = Date.now();
      const manager = createSlackSnapshotManager(
        runningConnectedSlackAccount({
          lastStartAt: now - STALE_THRESHOLD - 60_000,
          lastEventAt: now - 5_000,
        }),
      );
      await expectNoRestart(manager);
    });

    (deftest "skips channels still within the startup grace window for stale detection", async () => {
      const now = Date.now();
      const manager = createSlackSnapshotManager(
        runningConnectedSlackAccount({
          lastStartAt: now - 5_000,
          lastEventAt: null,
        }),
      );
      await expectNoRestart(manager);
    });

    (deftest "restarts a channel that has seen no events since connect past the stale threshold", async () => {
      const now = Date.now();
      const manager = createSlackSnapshotManager(
        runningConnectedSlackAccount({
          lastStartAt: now - STALE_THRESHOLD - 60_000,
          lastEventAt: now - STALE_THRESHOLD - 60_000,
        }),
      );
      await expectRestartedChannel(manager, "slack");
    });

    (deftest "skips connected channels that do not report event liveness", async () => {
      const now = Date.now();
      const manager = createSnapshotManager({
        telegram: {
          default: {
            running: true,
            connected: true,
            enabled: true,
            configured: true,
            lastStartAt: now - STALE_THRESHOLD - 60_000,
            lastEventAt: null,
          },
        },
      });
      await expectNoRestart(manager);
    });

    (deftest "respects custom staleEventThresholdMs", async () => {
      const customThreshold = 10 * 60_000;
      const now = Date.now();
      const manager = createSlackSnapshotManager(
        runningConnectedSlackAccount({
          lastStartAt: now - customThreshold - 60_000,
          lastEventAt: now - customThreshold - 30_000,
        }),
      );
      const monitor = await startAndRunCheck(manager, {
        staleEventThresholdMs: customThreshold,
      });
      (expect* manager.stopChannel).toHaveBeenCalledWith("slack", "default");
      (expect* manager.startChannel).toHaveBeenCalledWith("slack", "default");
      monitor.stop();
    });
  });
});
