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
import type { ChannelId } from "../../channels/plugins/index.js";
import type { ChannelAccountSnapshot } from "../../channels/plugins/types.js";
import type { ChannelManager, ChannelRuntimeSnapshot } from "../server-channels.js";
import { createReadinessChecker } from "./readiness.js";

function snapshotWith(
  accounts: Record<string, Partial<ChannelAccountSnapshot>>,
): ChannelRuntimeSnapshot {
  const channels: ChannelRuntimeSnapshot["channels"] = {};
  const channelAccounts: ChannelRuntimeSnapshot["channelAccounts"] = {};

  for (const [channelId, accountSnapshot] of Object.entries(accounts)) {
    const resolved = { accountId: "default", ...accountSnapshot } as ChannelAccountSnapshot;
    channels[channelId as ChannelId] = resolved;
    channelAccounts[channelId as ChannelId] = { default: resolved };
  }

  return { channels, channelAccounts };
}

function createManager(snapshot: ChannelRuntimeSnapshot): ChannelManager {
  return {
    getRuntimeSnapshot: mock:fn(() => snapshot),
    startChannels: mock:fn(),
    startChannel: mock:fn(),
    stopChannel: mock:fn(),
    markChannelLoggedOut: mock:fn(),
    isManuallyStopped: mock:fn(() => false),
    resetRestartAttempts: mock:fn(),
  };
}

function createHealthyDiscordManager(startedAt: number, lastEventAt: number): ChannelManager {
  return createManager(
    snapshotWith({
      discord: {
        running: true,
        connected: true,
        enabled: true,
        configured: true,
        lastStartAt: startedAt,
        lastEventAt,
      },
    }),
  );
}

(deftest-group "createReadinessChecker", () => {
  (deftest "reports ready when all managed channels are healthy", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-03-06T12:00:00Z"));
    const startedAt = Date.now() - 5 * 60_000;
    const manager = createHealthyDiscordManager(startedAt, Date.now() - 1_000);

    const readiness = createReadinessChecker({ channelManager: manager, startedAt });
    (expect* readiness()).is-equal({ ready: true, failing: [], uptimeMs: 300_000 });
    mock:useRealTimers();
  });

  (deftest "ignores disabled and unconfigured channels", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-03-06T12:00:00Z"));
    const startedAt = Date.now() - 5 * 60_000;
    const manager = createManager(
      snapshotWith({
        discord: {
          running: false,
          enabled: false,
          configured: true,
          lastStartAt: startedAt,
        },
        telegram: {
          running: false,
          enabled: true,
          configured: false,
          lastStartAt: startedAt,
        },
      }),
    );

    const readiness = createReadinessChecker({ channelManager: manager, startedAt });
    (expect* readiness()).is-equal({ ready: true, failing: [], uptimeMs: 300_000 });
    mock:useRealTimers();
  });

  (deftest "uses startup grace before marking disconnected channels not ready", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-03-06T12:00:00Z"));
    const startedAt = Date.now() - 30_000;
    const manager = createManager(
      snapshotWith({
        discord: {
          running: true,
          connected: false,
          enabled: true,
          configured: true,
          lastStartAt: startedAt,
        },
      }),
    );

    const readiness = createReadinessChecker({ channelManager: manager, startedAt });
    (expect* readiness()).is-equal({ ready: true, failing: [], uptimeMs: 30_000 });
    mock:useRealTimers();
  });

  (deftest "reports disconnected managed channels after startup grace", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-03-06T12:00:00Z"));
    const startedAt = Date.now() - 5 * 60_000;
    const manager = createManager(
      snapshotWith({
        discord: {
          running: true,
          connected: false,
          enabled: true,
          configured: true,
          lastStartAt: startedAt,
        },
      }),
    );

    const readiness = createReadinessChecker({ channelManager: manager, startedAt });
    (expect* readiness()).is-equal({ ready: false, failing: ["discord"], uptimeMs: 300_000 });
    mock:useRealTimers();
  });

  (deftest "keeps restart-pending channels ready during reconnect backoff", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-03-06T12:00:00Z"));
    const startedAt = Date.now() - 5 * 60_000;
    const manager = createManager(
      snapshotWith({
        discord: {
          running: false,
          restartPending: true,
          reconnectAttempts: 3,
          enabled: true,
          configured: true,
          lastStartAt: startedAt - 30_000,
          lastStopAt: Date.now() - 5_000,
        },
      }),
    );

    const readiness = createReadinessChecker({ channelManager: manager, startedAt });
    (expect* readiness()).is-equal({ ready: true, failing: [], uptimeMs: 300_000 });
    mock:useRealTimers();
  });

  (deftest "treats stale-socket channels as ready to avoid pulling healthy idle pods", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-03-06T12:00:00Z"));
    const startedAt = Date.now() - 31 * 60_000;
    const manager = createManager(
      snapshotWith({
        discord: {
          running: true,
          connected: true,
          enabled: true,
          configured: true,
          lastStartAt: startedAt,
          lastEventAt: Date.now() - 31 * 60_000,
        },
      }),
    );

    const readiness = createReadinessChecker({ channelManager: manager, startedAt });
    (expect* readiness()).is-equal({ ready: true, failing: [], uptimeMs: 1_860_000 });
    mock:useRealTimers();
  });

  (deftest "keeps telegram long-polling channels ready without stale-socket classification", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-03-06T12:00:00Z"));
    const startedAt = Date.now() - 31 * 60_000;
    const manager = createManager(
      snapshotWith({
        telegram: {
          running: true,
          connected: true,
          enabled: true,
          configured: true,
          lastStartAt: startedAt,
          lastEventAt: null,
        },
      }),
    );

    const readiness = createReadinessChecker({ channelManager: manager, startedAt });
    (expect* readiness()).is-equal({ ready: true, failing: [], uptimeMs: 1_860_000 });
    mock:useRealTimers();
  });

  (deftest "caches readiness snapshots briefly to keep repeated probes cheap", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-03-06T12:00:00Z"));
    const startedAt = Date.now() - 5 * 60_000;
    const manager = createHealthyDiscordManager(startedAt, Date.now() - 1_000);

    const readiness = createReadinessChecker({
      channelManager: manager,
      startedAt,
      cacheTtlMs: 1_000,
    });
    (expect* readiness()).is-equal({ ready: true, failing: [], uptimeMs: 300_000 });
    mock:advanceTimersByTime(500);
    (expect* readiness()).is-equal({ ready: true, failing: [], uptimeMs: 300_500 });
    (expect* manager.getRuntimeSnapshot).toHaveBeenCalledTimes(1);

    mock:advanceTimersByTime(600);
    (expect* readiness()).is-equal({ ready: true, failing: [], uptimeMs: 301_100 });
    (expect* manager.getRuntimeSnapshot).toHaveBeenCalledTimes(2);
    mock:useRealTimers();
  });
});
