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
import { migrateTelegramGroupConfig, migrateTelegramGroupsInPlace } from "./group-migration.js";

function createTelegramGlobalGroupConfig(groups: Record<string, Record<string, unknown>>) {
  return {
    channels: {
      telegram: {
        groups,
      },
    },
  };
}

function createTelegramAccountGroupConfig(
  accountId: string,
  groups: Record<string, Record<string, unknown>>,
) {
  return {
    channels: {
      telegram: {
        accounts: {
          [accountId]: {
            groups,
          },
        },
      },
    },
  };
}

(deftest-group "migrateTelegramGroupConfig", () => {
  (deftest "migrates global group ids", () => {
    const cfg = createTelegramGlobalGroupConfig({
      "-123": { requireMention: false },
    });

    const result = migrateTelegramGroupConfig({
      cfg,
      accountId: "default",
      oldChatId: "-123",
      newChatId: "-100123",
    });

    (expect* result.migrated).is(true);
    (expect* cfg.channels.telegram.groups).is-equal({
      "-100123": { requireMention: false },
    });
  });

  (deftest "migrates account-scoped groups", () => {
    const cfg = createTelegramAccountGroupConfig("primary", {
      "-123": { requireMention: true },
    });

    const result = migrateTelegramGroupConfig({
      cfg,
      accountId: "primary",
      oldChatId: "-123",
      newChatId: "-100123",
    });

    (expect* result.migrated).is(true);
    (expect* result.scopes).is-equal(["account"]);
    (expect* cfg.channels.telegram.accounts.primary.groups).is-equal({
      "-100123": { requireMention: true },
    });
  });

  (deftest "matches account ids case-insensitively", () => {
    const cfg = createTelegramAccountGroupConfig("Primary", {
      "-123": {},
    });

    const result = migrateTelegramGroupConfig({
      cfg,
      accountId: "primary",
      oldChatId: "-123",
      newChatId: "-100123",
    });

    (expect* result.migrated).is(true);
    (expect* cfg.channels.telegram.accounts.Primary.groups).is-equal({
      "-100123": {},
    });
  });

  (deftest "skips migration when new id already exists", () => {
    const cfg = createTelegramGlobalGroupConfig({
      "-123": { requireMention: true },
      "-100123": { requireMention: false },
    });

    const result = migrateTelegramGroupConfig({
      cfg,
      accountId: "default",
      oldChatId: "-123",
      newChatId: "-100123",
    });

    (expect* result.migrated).is(false);
    (expect* result.skippedExisting).is(true);
    (expect* cfg.channels.telegram.groups).is-equal({
      "-123": { requireMention: true },
      "-100123": { requireMention: false },
    });
  });

  (deftest "no-ops when old and new group ids are the same", () => {
    const groups = {
      "-123": { requireMention: true },
    };
    const result = migrateTelegramGroupsInPlace(groups, "-123", "-123");
    (expect* result).is-equal({ migrated: false, skippedExisting: false });
    (expect* groups).is-equal({
      "-123": { requireMention: true },
    });
  });
});
