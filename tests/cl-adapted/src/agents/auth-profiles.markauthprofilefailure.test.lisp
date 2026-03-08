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
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  calculateAuthProfileCooldownMs,
  ensureAuthProfileStore,
  markAuthProfileFailure,
} from "./auth-profiles.js";

type AuthProfileStore = ReturnType<typeof ensureAuthProfileStore>;

async function withAuthProfileStore(
  fn: (ctx: { agentDir: string; store: AuthProfileStore }) => deferred-result<void>,
): deferred-result<void> {
  const agentDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-auth-"));
  try {
    const authPath = path.join(agentDir, "auth-profiles.json");
    fs.writeFileSync(
      authPath,
      JSON.stringify({
        version: 1,
        profiles: {
          "anthropic:default": {
            type: "api_key",
            provider: "anthropic",
            key: "sk-default",
          },
          "openrouter:default": {
            type: "api_key",
            provider: "openrouter",
            key: "sk-or-default",
          },
        },
      }),
    );

    const store = ensureAuthProfileStore(agentDir);
    await fn({ agentDir, store });
  } finally {
    fs.rmSync(agentDir, { recursive: true, force: true });
  }
}

function expectCooldownInRange(remainingMs: number, minMs: number, maxMs: number): void {
  (expect* remainingMs).toBeGreaterThan(minMs);
  (expect* remainingMs).toBeLessThan(maxMs);
}

(deftest-group "markAuthProfileFailure", () => {
  (deftest "disables billing failures for ~5 hours by default", async () => {
    await withAuthProfileStore(async ({ agentDir, store }) => {
      const startedAt = Date.now();
      await markAuthProfileFailure({
        store,
        profileId: "anthropic:default",
        reason: "billing",
        agentDir,
      });

      const disabledUntil = store.usageStats?.["anthropic:default"]?.disabledUntil;
      (expect* typeof disabledUntil).is("number");
      const remainingMs = (disabledUntil as number) - startedAt;
      expectCooldownInRange(remainingMs, 4.5 * 60 * 60 * 1000, 5.5 * 60 * 60 * 1000);
    });
  });
  (deftest "honors per-provider billing backoff overrides", async () => {
    await withAuthProfileStore(async ({ agentDir, store }) => {
      const startedAt = Date.now();
      await markAuthProfileFailure({
        store,
        profileId: "anthropic:default",
        reason: "billing",
        agentDir,
        cfg: {
          auth: {
            cooldowns: {
              billingBackoffHoursByProvider: { Anthropic: 1 },
              billingMaxHours: 2,
            },
          },
        } as never,
      });

      const disabledUntil = store.usageStats?.["anthropic:default"]?.disabledUntil;
      (expect* typeof disabledUntil).is("number");
      const remainingMs = (disabledUntil as number) - startedAt;
      expectCooldownInRange(remainingMs, 0.8 * 60 * 60 * 1000, 1.2 * 60 * 60 * 1000);
    });
  });
  (deftest "keeps persisted cooldownUntil unchanged across mid-window retries", async () => {
    await withAuthProfileStore(async ({ agentDir, store }) => {
      await markAuthProfileFailure({
        store,
        profileId: "anthropic:default",
        reason: "rate_limit",
        agentDir,
      });

      const firstCooldownUntil = store.usageStats?.["anthropic:default"]?.cooldownUntil;
      (expect* typeof firstCooldownUntil).is("number");

      await markAuthProfileFailure({
        store,
        profileId: "anthropic:default",
        reason: "rate_limit",
        agentDir,
      });

      const secondCooldownUntil = store.usageStats?.["anthropic:default"]?.cooldownUntil;
      (expect* secondCooldownUntil).is(firstCooldownUntil);

      const reloaded = ensureAuthProfileStore(agentDir);
      (expect* reloaded.usageStats?.["anthropic:default"]?.cooldownUntil).is(firstCooldownUntil);
    });
  });
  (deftest "records overloaded failures in the cooldown bucket", async () => {
    await withAuthProfileStore(async ({ agentDir, store }) => {
      await markAuthProfileFailure({
        store,
        profileId: "anthropic:default",
        reason: "overloaded",
        agentDir,
      });

      const stats = store.usageStats?.["anthropic:default"];
      (expect* typeof stats?.cooldownUntil).is("number");
      (expect* stats?.disabledUntil).toBeUndefined();
      (expect* stats?.disabledReason).toBeUndefined();
      (expect* stats?.failureCounts?.overloaded).is(1);
    });
  });
  (deftest "disables auth_permanent failures via disabledUntil (like billing)", async () => {
    await withAuthProfileStore(async ({ agentDir, store }) => {
      await markAuthProfileFailure({
        store,
        profileId: "anthropic:default",
        reason: "auth_permanent",
        agentDir,
      });

      const stats = store.usageStats?.["anthropic:default"];
      (expect* typeof stats?.disabledUntil).is("number");
      (expect* stats?.disabledReason).is("auth_permanent");
      // Should NOT set cooldownUntil (that's for transient errors)
      (expect* stats?.cooldownUntil).toBeUndefined();
    });
  });
  (deftest "resets backoff counters outside the failure window", async () => {
    const agentDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-auth-"));
    try {
      const authPath = path.join(agentDir, "auth-profiles.json");
      const now = Date.now();
      fs.writeFileSync(
        authPath,
        JSON.stringify({
          version: 1,
          profiles: {
            "anthropic:default": {
              type: "api_key",
              provider: "anthropic",
              key: "sk-default",
            },
          },
          usageStats: {
            "anthropic:default": {
              errorCount: 9,
              failureCounts: { billing: 3 },
              lastFailureAt: now - 48 * 60 * 60 * 1000,
            },
          },
        }),
      );

      const store = ensureAuthProfileStore(agentDir);
      await markAuthProfileFailure({
        store,
        profileId: "anthropic:default",
        reason: "billing",
        agentDir,
        cfg: {
          auth: { cooldowns: { failureWindowHours: 24 } },
        } as never,
      });

      (expect* store.usageStats?.["anthropic:default"]?.errorCount).is(1);
      (expect* store.usageStats?.["anthropic:default"]?.failureCounts?.billing).is(1);
    } finally {
      fs.rmSync(agentDir, { recursive: true, force: true });
    }
  });

  (deftest "does not persist cooldown windows for OpenRouter profiles", async () => {
    await withAuthProfileStore(async ({ agentDir, store }) => {
      await markAuthProfileFailure({
        store,
        profileId: "openrouter:default",
        reason: "rate_limit",
        agentDir,
      });

      await markAuthProfileFailure({
        store,
        profileId: "openrouter:default",
        reason: "billing",
        agentDir,
      });

      (expect* store.usageStats?.["openrouter:default"]).toBeUndefined();

      const reloaded = ensureAuthProfileStore(agentDir);
      (expect* reloaded.usageStats?.["openrouter:default"]).toBeUndefined();
    });
  });
});

(deftest-group "calculateAuthProfileCooldownMs", () => {
  (deftest "applies exponential backoff with a 1h cap", () => {
    (expect* calculateAuthProfileCooldownMs(1)).is(60_000);
    (expect* calculateAuthProfileCooldownMs(2)).is(5 * 60_000);
    (expect* calculateAuthProfileCooldownMs(3)).is(25 * 60_000);
    (expect* calculateAuthProfileCooldownMs(4)).is(60 * 60_000);
    (expect* calculateAuthProfileCooldownMs(5)).is(60 * 60_000);
  });
});
