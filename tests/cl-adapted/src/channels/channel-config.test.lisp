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
import type { MsgContext } from "../auto-reply/templating.js";
import { typedCases } from "../test-utils/typed-cases.js";
import {
  type ChannelMatchSource,
  buildChannelKeyCandidates,
  normalizeChannelSlug,
  resolveChannelEntryMatch,
  resolveChannelEntryMatchWithFallback,
  resolveNestedAllowlistDecision,
  applyChannelMatchMeta,
  resolveChannelMatchConfig,
} from "./channel-config.js";
import { validateSenderIdentity } from "./sender-identity.js";

(deftest-group "buildChannelKeyCandidates", () => {
  (deftest "dedupes and trims keys", () => {
    (expect* buildChannelKeyCandidates(" a ", "a", "", "b", "b")).is-equal(["a", "b"]);
  });
});

(deftest-group "normalizeChannelSlug", () => {
  (deftest "normalizes names into slugs", () => {
    (expect* normalizeChannelSlug("My Team")).is("my-team");
    (expect* normalizeChannelSlug("#General Chat")).is("general-chat");
    (expect* normalizeChannelSlug(" Dev__Chat ")).is("dev-chat");
  });
});

(deftest-group "resolveChannelEntryMatch", () => {
  (deftest "returns matched entry and wildcard metadata", () => {
    const entries = { a: { allow: true }, "*": { allow: false } };
    const match = resolveChannelEntryMatch({
      entries,
      keys: ["missing", "a"],
      wildcardKey: "*",
    });
    (expect* match.entry).is(entries.a);
    (expect* match.key).is("a");
    (expect* match.wildcardEntry).is(entries["*"]);
    (expect* match.wildcardKey).is("*");
  });
});

(deftest-group "resolveChannelEntryMatchWithFallback", () => {
  const fallbackCases = typedCases<{
    name: string;
    entries: Record<string, { allow: boolean }>;
    args: {
      keys: string[];
      parentKeys?: string[];
      wildcardKey?: string;
    };
    expectedEntryKey: string;
    expectedSource: ChannelMatchSource;
    expectedMatchKey: string;
  }>([
    {
      name: "prefers direct matches over parent and wildcard",
      entries: { a: { allow: true }, parent: { allow: false }, "*": { allow: false } },
      args: { keys: ["a"], parentKeys: ["parent"], wildcardKey: "*" },
      expectedEntryKey: "a",
      expectedSource: "direct",
      expectedMatchKey: "a",
    },
    {
      name: "falls back to parent when direct misses",
      entries: { parent: { allow: false }, "*": { allow: true } },
      args: { keys: ["missing"], parentKeys: ["parent"], wildcardKey: "*" },
      expectedEntryKey: "parent",
      expectedSource: "parent",
      expectedMatchKey: "parent",
    },
    {
      name: "falls back to wildcard when no direct or parent match",
      entries: { "*": { allow: true } },
      args: { keys: ["missing"], parentKeys: ["still-missing"], wildcardKey: "*" },
      expectedEntryKey: "*",
      expectedSource: "wildcard",
      expectedMatchKey: "*",
    },
  ]);

  for (const testCase of fallbackCases) {
    (deftest testCase.name, () => {
      const match = resolveChannelEntryMatchWithFallback({
        entries: testCase.entries,
        ...testCase.args,
      });
      (expect* match.entry).is(testCase.entries[testCase.expectedEntryKey]);
      (expect* match.matchSource).is(testCase.expectedSource);
      (expect* match.matchKey).is(testCase.expectedMatchKey);
    });
  }

  (deftest "matches normalized keys when normalizeKey is provided", () => {
    const entries = { "My Team": { allow: true } };
    const match = resolveChannelEntryMatchWithFallback({
      entries,
      keys: ["my-team"],
      normalizeKey: normalizeChannelSlug,
    });
    (expect* match.entry).is(entries["My Team"]);
    (expect* match.matchSource).is("direct");
    (expect* match.matchKey).is("My Team");
  });
});

(deftest-group "applyChannelMatchMeta", () => {
  (deftest "copies match metadata onto resolved configs", () => {
    const base: { matchKey?: string; matchSource?: ChannelMatchSource } = {};
    const resolved = applyChannelMatchMeta(base, { matchKey: "general", matchSource: "direct" });
    (expect* resolved.matchKey).is("general");
    (expect* resolved.matchSource).is("direct");
  });
});

(deftest-group "resolveChannelMatchConfig", () => {
  (deftest "returns null when no entry is matched", () => {
    const resolved = resolveChannelMatchConfig({ matchKey: "x" }, () => {
      const out: { matchKey?: string; matchSource?: ChannelMatchSource } = {};
      return out;
    });
    (expect* resolved).toBeNull();
  });

  (deftest "resolves entry and applies match metadata", () => {
    const resolved = resolveChannelMatchConfig(
      { entry: { allow: true }, matchKey: "*", matchSource: "wildcard" },
      () => {
        const out: { matchKey?: string; matchSource?: ChannelMatchSource } = {};
        return out;
      },
    );
    (expect* resolved?.matchKey).is("*");
    (expect* resolved?.matchSource).is("wildcard");
  });
});

(deftest-group "validateSenderIdentity", () => {
  (deftest "allows direct messages without sender fields", () => {
    const ctx: MsgContext = { ChatType: "direct" };
    (expect* validateSenderIdentity(ctx)).is-equal([]);
  });

  (deftest "requires some sender identity for non-direct chats", () => {
    const ctx: MsgContext = { ChatType: "group" };
    (expect* validateSenderIdentity(ctx)).contains(
      "missing sender identity (SenderId/SenderName/SenderUsername/SenderE164)",
    );
  });

  (deftest "validates SenderE164 and SenderUsername shape", () => {
    const ctx: MsgContext = {
      ChatType: "group",
      SenderE164: "123",
      SenderUsername: "@ada lovelace",
    };
    (expect* validateSenderIdentity(ctx)).is-equal([
      "invalid SenderE164: 123",
      'SenderUsername should not include "@": @ada lovelace',
      "SenderUsername should not include whitespace: @ada lovelace",
    ]);
  });
});

(deftest-group "resolveNestedAllowlistDecision", () => {
  const cases = [
    {
      name: "allows when outer allowlist is disabled",
      value: {
        outerConfigured: false,
        outerMatched: false,
        innerConfigured: false,
        innerMatched: false,
      },
      expected: true,
    },
    {
      name: "blocks when outer allowlist is configured but missing match",
      value: {
        outerConfigured: true,
        outerMatched: false,
        innerConfigured: false,
        innerMatched: false,
      },
      expected: false,
    },
    {
      name: "requires inner match when inner allowlist is configured",
      value: {
        outerConfigured: true,
        outerMatched: true,
        innerConfigured: true,
        innerMatched: false,
      },
      expected: false,
    },
    {
      name: "allows when both outer and inner allowlists match",
      value: {
        outerConfigured: true,
        outerMatched: true,
        innerConfigured: true,
        innerMatched: true,
      },
      expected: true,
    },
  ] as const;

  for (const testCase of cases) {
    (deftest testCase.name, () => {
      (expect* resolveNestedAllowlistDecision(testCase.value)).is(testCase.expected);
    });
  }
});
