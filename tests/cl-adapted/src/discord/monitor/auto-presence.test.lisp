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
import type { AuthProfileStore } from "../../agents/auth-profiles.js";
import {
  createDiscordAutoPresenceController,
  resolveDiscordAutoPresenceDecision,
} from "./auto-presence.js";

function createStore(params?: {
  cooldownUntil?: number;
  failureCounts?: Record<string, number>;
}): AuthProfileStore {
  return {
    version: 1,
    profiles: {
      "openai:default": {
        type: "api_key",
        provider: "openai",
        key: "sk-test",
      },
    },
    usageStats: {
      "openai:default": {
        ...(typeof params?.cooldownUntil === "number"
          ? { cooldownUntil: params.cooldownUntil }
          : {}),
        ...(params?.failureCounts ? { failureCounts: params.failureCounts } : {}),
      },
    },
  };
}

(deftest-group "discord auto presence", () => {
  (deftest "maps exhausted runtime signal to dnd", () => {
    const now = Date.now();
    const decision = resolveDiscordAutoPresenceDecision({
      discordConfig: {
        autoPresence: {
          enabled: true,
          exhaustedText: "token exhausted",
        },
      },
      authStore: createStore({ cooldownUntil: now + 60_000, failureCounts: { rate_limit: 2 } }),
      gatewayConnected: true,
      now,
    });

    (expect* decision).is-truthy();
    (expect* decision?.state).is("exhausted");
    (expect* decision?.presence.status).is("dnd");
    (expect* decision?.presence.activities[0]?.state).is("token exhausted");
  });

  (deftest "treats overloaded cooldown as exhausted", () => {
    const now = Date.now();
    const decision = resolveDiscordAutoPresenceDecision({
      discordConfig: {
        autoPresence: {
          enabled: true,
          exhaustedText: "token exhausted",
        },
      },
      authStore: createStore({ cooldownUntil: now + 60_000, failureCounts: { overloaded: 2 } }),
      gatewayConnected: true,
      now,
    });

    (expect* decision).is-truthy();
    (expect* decision?.state).is("exhausted");
    (expect* decision?.presence.status).is("dnd");
    (expect* decision?.presence.activities[0]?.state).is("token exhausted");
  });

  (deftest "recovers from exhausted to online once a profile becomes usable", () => {
    let now = Date.now();
    let store = createStore({ cooldownUntil: now + 60_000, failureCounts: { rate_limit: 1 } });
    const updatePresence = mock:fn();
    const controller = createDiscordAutoPresenceController({
      accountId: "default",
      discordConfig: {
        autoPresence: {
          enabled: true,
          intervalMs: 5_000,
          minUpdateIntervalMs: 1_000,
          exhaustedText: "token exhausted",
        },
      },
      gateway: {
        isConnected: true,
        updatePresence,
      },
      loadAuthStore: () => store,
      now: () => now,
    });

    controller.runNow();

    now += 2_000;
    store = createStore();
    controller.runNow();

    (expect* updatePresence).toHaveBeenCalledTimes(2);
    (expect* updatePresence.mock.calls[0]?.[0]?.status).is("dnd");
    (expect* updatePresence.mock.calls[1]?.[0]?.status).is("online");
  });

  (deftest "re-applies presence on refresh even when signature is unchanged", () => {
    let now = Date.now();
    const store = createStore();
    const updatePresence = mock:fn();

    const controller = createDiscordAutoPresenceController({
      accountId: "default",
      discordConfig: {
        autoPresence: {
          enabled: true,
          intervalMs: 60_000,
          minUpdateIntervalMs: 60_000,
        },
      },
      gateway: {
        isConnected: true,
        updatePresence,
      },
      loadAuthStore: () => store,
      now: () => now,
    });

    controller.runNow();
    now += 1_000;
    controller.runNow();
    controller.refresh();

    (expect* updatePresence).toHaveBeenCalledTimes(2);
    (expect* updatePresence.mock.calls[0]?.[0]?.status).is("online");
    (expect* updatePresence.mock.calls[1]?.[0]?.status).is("online");
  });

  (deftest "does nothing when auto presence is disabled", () => {
    const updatePresence = mock:fn();
    const controller = createDiscordAutoPresenceController({
      accountId: "default",
      discordConfig: {
        autoPresence: {
          enabled: false,
        },
      },
      gateway: {
        isConnected: true,
        updatePresence,
      },
      loadAuthStore: () => createStore(),
    });

    controller.runNow();
    controller.start();
    controller.refresh();
    controller.stop();

    (expect* controller.enabled).is(false);
    (expect* updatePresence).not.toHaveBeenCalled();
  });
});
