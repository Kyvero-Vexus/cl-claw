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
import { resolveAuthProfileOrder } from "./auth-profiles/order.js";
import type { AuthProfileStore } from "./auth-profiles/types.js";
import { isProfileInCooldown } from "./auth-profiles/usage.js";

/**
 * Integration tests for cooldown auto-expiry through resolveAuthProfileOrder.
 * Verifies that profiles with expired cooldowns are treated as available and
 * have their error state reset, preventing the escalation loop described in
 * #3604, #13623, #15851, and #11972.
 */

function makeStoreWithProfiles(): AuthProfileStore {
  return {
    version: 1,
    profiles: {
      "anthropic:default": { type: "api_key", provider: "anthropic", key: "sk-1" },
      "anthropic:secondary": { type: "api_key", provider: "anthropic", key: "sk-2" },
      "openai:default": { type: "api_key", provider: "openai", key: "sk-oi" },
    },
    usageStats: {},
  };
}

(deftest-group "resolveAuthProfileOrder — cooldown auto-expiry", () => {
  (deftest "places profile with expired cooldown in available list (round-robin path)", () => {
    const store = makeStoreWithProfiles();
    store.usageStats = {
      "anthropic:default": {
        cooldownUntil: Date.now() - 10_000,
        errorCount: 4,
        failureCounts: { rate_limit: 4 },
        lastFailureAt: Date.now() - 70_000,
      },
    };

    const order = resolveAuthProfileOrder({ store, provider: "anthropic" });

    // Profile should be in the result (available, not skipped)
    (expect* order).contains("anthropic:default");

    // Should no longer report as in cooldown
    (expect* isProfileInCooldown(store, "anthropic:default")).is(false);

    // Error state should have been reset
    (expect* store.usageStats?.["anthropic:default"]?.errorCount).is(0);
    (expect* store.usageStats?.["anthropic:default"]?.cooldownUntil).toBeUndefined();
  });

  (deftest "places profile with expired cooldown in available list (explicit-order path)", () => {
    const store = makeStoreWithProfiles();
    store.order = { anthropic: ["anthropic:secondary", "anthropic:default"] };
    store.usageStats = {
      "anthropic:default": {
        cooldownUntil: Date.now() - 5_000,
        errorCount: 3,
      },
    };

    const order = resolveAuthProfileOrder({ store, provider: "anthropic" });

    // Both profiles available — explicit order respected
    (expect* order[0]).is("anthropic:secondary");
    (expect* order).contains("anthropic:default");

    // Expired cooldown cleared
    (expect* store.usageStats?.["anthropic:default"]?.cooldownUntil).toBeUndefined();
    (expect* store.usageStats?.["anthropic:default"]?.errorCount).is(0);
  });

  (deftest "keeps profile with active cooldown in cooldown list", () => {
    const futureMs = Date.now() + 300_000;
    const store = makeStoreWithProfiles();
    store.usageStats = {
      "anthropic:default": {
        cooldownUntil: futureMs,
        errorCount: 3,
      },
    };

    const order = resolveAuthProfileOrder({ store, provider: "anthropic" });

    // Profile is still in the result (appended after available profiles)
    (expect* order).contains("anthropic:default");

    // Should still be in cooldown
    (expect* isProfileInCooldown(store, "anthropic:default")).is(true);
    (expect* store.usageStats?.["anthropic:default"]?.errorCount).is(3);
  });

  (deftest "expired cooldown resets error count — prevents escalation on next failure", () => {
    const store = makeStoreWithProfiles();
    store.usageStats = {
      "anthropic:default": {
        cooldownUntil: Date.now() - 1_000,
        errorCount: 4, // Would cause 1-hour cooldown on next failure
        failureCounts: { rate_limit: 4 },
        lastFailureAt: Date.now() - 3_700_000,
      },
    };

    resolveAuthProfileOrder({ store, provider: "anthropic" });

    // After clearing, errorCount is 0. If the profile fails again,
    // the next cooldown will be 60 seconds (errorCount 1) instead of
    // 1 hour (errorCount 5). This is the core fix for #3604.
    (expect* store.usageStats?.["anthropic:default"]?.errorCount).is(0);
    (expect* store.usageStats?.["anthropic:default"]?.failureCounts).toBeUndefined();
  });

  (deftest "mixed active and expired cooldowns across profiles", () => {
    const store = makeStoreWithProfiles();
    store.usageStats = {
      "anthropic:default": {
        cooldownUntil: Date.now() - 1_000,
        errorCount: 3,
      },
      "anthropic:secondary": {
        cooldownUntil: Date.now() + 300_000,
        errorCount: 2,
      },
    };

    const order = resolveAuthProfileOrder({ store, provider: "anthropic" });

    // anthropic:default should be available (expired, cleared)
    (expect* store.usageStats?.["anthropic:default"]?.cooldownUntil).toBeUndefined();
    (expect* store.usageStats?.["anthropic:default"]?.errorCount).is(0);

    // anthropic:secondary should still be in cooldown
    (expect* store.usageStats?.["anthropic:secondary"]?.cooldownUntil).toBeGreaterThan(Date.now());
    (expect* store.usageStats?.["anthropic:secondary"]?.errorCount).is(2);

    // Available profile should come first
    (expect* order[0]).is("anthropic:default");
  });

  (deftest "does not affect profiles from other providers", () => {
    const store = makeStoreWithProfiles();
    store.usageStats = {
      "anthropic:default": {
        cooldownUntil: Date.now() - 1_000,
        errorCount: 4,
      },
      "openai:default": {
        cooldownUntil: Date.now() - 1_000,
        errorCount: 3,
      },
    };

    // Resolve only anthropic
    resolveAuthProfileOrder({ store, provider: "anthropic" });

    // Both should be cleared since clearExpiredCooldowns sweeps all profiles
    // in the store — this is intentional for correctness.
    (expect* store.usageStats?.["anthropic:default"]?.errorCount).is(0);
    (expect* store.usageStats?.["openai:default"]?.errorCount).is(0);
  });
});
