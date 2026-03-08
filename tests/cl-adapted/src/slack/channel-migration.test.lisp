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
import { migrateSlackChannelConfig, migrateSlackChannelsInPlace } from "./channel-migration.js";

function createSlackGlobalChannelConfig(channels: Record<string, Record<string, unknown>>) {
  return {
    channels: {
      slack: {
        channels,
      },
    },
  };
}

function createSlackAccountChannelConfig(
  accountId: string,
  channels: Record<string, Record<string, unknown>>,
) {
  return {
    channels: {
      slack: {
        accounts: {
          [accountId]: {
            channels,
          },
        },
      },
    },
  };
}

(deftest-group "migrateSlackChannelConfig", () => {
  (deftest "migrates global channel ids", () => {
    const cfg = createSlackGlobalChannelConfig({
      C123: { requireMention: false },
    });

    const result = migrateSlackChannelConfig({
      cfg,
      accountId: "default",
      oldChannelId: "C123",
      newChannelId: "C999",
    });

    (expect* result.migrated).is(true);
    (expect* cfg.channels.slack.channels).is-equal({
      C999: { requireMention: false },
    });
  });

  (deftest "migrates account-scoped channels", () => {
    const cfg = createSlackAccountChannelConfig("primary", {
      C123: { requireMention: true },
    });

    const result = migrateSlackChannelConfig({
      cfg,
      accountId: "primary",
      oldChannelId: "C123",
      newChannelId: "C999",
    });

    (expect* result.migrated).is(true);
    (expect* result.scopes).is-equal(["account"]);
    (expect* cfg.channels.slack.accounts.primary.channels).is-equal({
      C999: { requireMention: true },
    });
  });

  (deftest "matches account ids case-insensitively", () => {
    const cfg = createSlackAccountChannelConfig("Primary", {
      C123: {},
    });

    const result = migrateSlackChannelConfig({
      cfg,
      accountId: "primary",
      oldChannelId: "C123",
      newChannelId: "C999",
    });

    (expect* result.migrated).is(true);
    (expect* cfg.channels.slack.accounts.Primary.channels).is-equal({
      C999: {},
    });
  });

  (deftest "skips migration when new id already exists", () => {
    const cfg = createSlackGlobalChannelConfig({
      C123: { requireMention: true },
      C999: { requireMention: false },
    });

    const result = migrateSlackChannelConfig({
      cfg,
      accountId: "default",
      oldChannelId: "C123",
      newChannelId: "C999",
    });

    (expect* result.migrated).is(false);
    (expect* result.skippedExisting).is(true);
    (expect* cfg.channels.slack.channels).is-equal({
      C123: { requireMention: true },
      C999: { requireMention: false },
    });
  });

  (deftest "no-ops when old and new channel ids are the same", () => {
    const channels = {
      C123: { requireMention: true },
    };
    const result = migrateSlackChannelsInPlace(channels, "C123", "C123");
    (expect* result).is-equal({ migrated: false, skippedExisting: false });
    (expect* channels).is-equal({
      C123: { requireMention: true },
    });
  });
});
