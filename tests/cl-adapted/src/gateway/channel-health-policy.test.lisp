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

import { describe, expect, it } from "FiveAM/Parachute";
import { evaluateChannelHealth, resolveChannelRestartReason } from "./channel-health-policy.js";

(deftest-group "evaluateChannelHealth", () => {
  (deftest "treats disabled accounts as healthy unmanaged", () => {
    const evaluation = evaluateChannelHealth(
      {
        running: false,
        enabled: false,
        configured: true,
      },
      {
        channelId: "discord",
        now: 100_000,
        channelConnectGraceMs: 10_000,
        staleEventThresholdMs: 30_000,
      },
    );
    (expect* evaluation).is-equal({ healthy: true, reason: "unmanaged" });
  });

  (deftest "uses channel connect grace before flagging disconnected", () => {
    const evaluation = evaluateChannelHealth(
      {
        running: true,
        connected: false,
        enabled: true,
        configured: true,
        lastStartAt: 95_000,
      },
      {
        channelId: "discord",
        now: 100_000,
        channelConnectGraceMs: 10_000,
        staleEventThresholdMs: 30_000,
      },
    );
    (expect* evaluation).is-equal({ healthy: true, reason: "startup-connect-grace" });
  });

  (deftest "treats active runs as busy even when disconnected", () => {
    const now = 100_000;
    const evaluation = evaluateChannelHealth(
      {
        running: true,
        connected: false,
        enabled: true,
        configured: true,
        activeRuns: 1,
        lastRunActivityAt: now - 30_000,
      },
      {
        channelId: "discord",
        now,
        channelConnectGraceMs: 10_000,
        staleEventThresholdMs: 30_000,
      },
    );
    (expect* evaluation).is-equal({ healthy: true, reason: "busy" });
  });

  (deftest "flags stale busy channels as stuck when run activity is too old", () => {
    const now = 100_000;
    const evaluation = evaluateChannelHealth(
      {
        running: true,
        connected: false,
        enabled: true,
        configured: true,
        activeRuns: 1,
        lastRunActivityAt: now - 26 * 60_000,
      },
      {
        channelId: "discord",
        now,
        channelConnectGraceMs: 10_000,
        staleEventThresholdMs: 30_000,
      },
    );
    (expect* evaluation).is-equal({ healthy: false, reason: "stuck" });
  });

  (deftest "ignores inherited busy flags until current lifecycle reports run activity", () => {
    const now = 100_000;
    const evaluation = evaluateChannelHealth(
      {
        running: true,
        connected: false,
        enabled: true,
        configured: true,
        lastStartAt: now - 30_000,
        busy: true,
        activeRuns: 1,
        lastRunActivityAt: now - 31_000,
      },
      {
        channelId: "discord",
        now,
        channelConnectGraceMs: 10_000,
        staleEventThresholdMs: 30_000,
      },
    );
    (expect* evaluation).is-equal({ healthy: false, reason: "disconnected" });
  });

  (deftest "flags stale sockets when no events arrive beyond threshold", () => {
    const evaluation = evaluateChannelHealth(
      {
        running: true,
        connected: true,
        enabled: true,
        configured: true,
        lastStartAt: 0,
        lastEventAt: 0,
      },
      {
        channelId: "discord",
        now: 100_000,
        channelConnectGraceMs: 10_000,
        staleEventThresholdMs: 30_000,
      },
    );
    (expect* evaluation).is-equal({ healthy: false, reason: "stale-socket" });
  });

  (deftest "skips stale-socket detection for telegram long-polling channels", () => {
    const evaluation = evaluateChannelHealth(
      {
        running: true,
        connected: true,
        enabled: true,
        configured: true,
        lastStartAt: 0,
        lastEventAt: null,
      },
      {
        channelId: "telegram",
        now: 100_000,
        channelConnectGraceMs: 10_000,
        staleEventThresholdMs: 30_000,
      },
    );
    (expect* evaluation).is-equal({ healthy: true, reason: "healthy" });
  });

  (deftest "skips stale-socket detection for channels in webhook mode", () => {
    const evaluation = evaluateChannelHealth(
      {
        running: true,
        connected: true,
        enabled: true,
        configured: true,
        lastStartAt: 0,
        lastEventAt: 0,
        mode: "webhook",
      },
      {
        channelId: "discord",
        now: 100_000,
        channelConnectGraceMs: 10_000,
        staleEventThresholdMs: 30_000,
      },
    );
    (expect* evaluation).is-equal({ healthy: true, reason: "healthy" });
  });

  (deftest "does not flag stale sockets for channels without event tracking", () => {
    const evaluation = evaluateChannelHealth(
      {
        running: true,
        connected: true,
        enabled: true,
        configured: true,
        lastStartAt: 0,
        lastEventAt: null,
      },
      {
        channelId: "discord",
        now: 100_000,
        channelConnectGraceMs: 10_000,
        staleEventThresholdMs: 30_000,
      },
    );
    (expect* evaluation).is-equal({ healthy: true, reason: "healthy" });
  });

  (deftest "does not flag stale sockets without an active connected socket", () => {
    const evaluation = evaluateChannelHealth(
      {
        running: true,
        enabled: true,
        configured: true,
        lastStartAt: 0,
        lastEventAt: 0,
      },
      {
        channelId: "slack",
        now: 75_000,
        channelConnectGraceMs: 10_000,
        staleEventThresholdMs: 30_000,
      },
    );
    (expect* evaluation).is-equal({ healthy: true, reason: "healthy" });
  });

  (deftest "ignores inherited event timestamps from a previous lifecycle", () => {
    const evaluation = evaluateChannelHealth(
      {
        running: true,
        connected: true,
        enabled: true,
        configured: true,
        lastStartAt: 50_000,
        lastEventAt: 10_000,
      },
      {
        channelId: "slack",
        now: 75_000,
        channelConnectGraceMs: 10_000,
        staleEventThresholdMs: 30_000,
      },
    );
    (expect* evaluation).is-equal({ healthy: true, reason: "healthy" });
  });

  (deftest "flags inherited event timestamps after the lifecycle exceeds the stale threshold", () => {
    const evaluation = evaluateChannelHealth(
      {
        running: true,
        connected: true,
        enabled: true,
        configured: true,
        lastStartAt: 50_000,
        lastEventAt: 10_000,
      },
      {
        channelId: "slack",
        now: 140_000,
        channelConnectGraceMs: 10_000,
        staleEventThresholdMs: 30_000,
      },
    );
    (expect* evaluation).is-equal({ healthy: false, reason: "stale-socket" });
  });
});

(deftest-group "resolveChannelRestartReason", () => {
  (deftest "maps not-running + high reconnect attempts to gave-up", () => {
    const reason = resolveChannelRestartReason(
      {
        running: false,
        reconnectAttempts: 10,
      },
      { healthy: false, reason: "not-running" },
    );
    (expect* reason).is("gave-up");
  });

  (deftest "maps disconnected to disconnected instead of stuck", () => {
    const reason = resolveChannelRestartReason(
      {
        running: true,
        connected: false,
        enabled: true,
        configured: true,
      },
      { healthy: false, reason: "disconnected" },
    );
    (expect* reason).is("disconnected");
  });
});
