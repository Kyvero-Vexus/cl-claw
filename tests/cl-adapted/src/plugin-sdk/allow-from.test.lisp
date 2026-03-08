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
import {
  formatAllowFromLowercase,
  formatNormalizedAllowFromEntries,
  isAllowedParsedChatSender,
  isNormalizedSenderAllowed,
} from "./allow-from.js";

function parseAllowTarget(
  entry: string,
):
  | { kind: "chat_id"; chatId: number }
  | { kind: "chat_guid"; chatGuid: string }
  | { kind: "chat_identifier"; chatIdentifier: string }
  | { kind: "handle"; handle: string } {
  const trimmed = entry.trim();
  const lower = trimmed.toLowerCase();
  if (lower.startsWith("chat_id:")) {
    return { kind: "chat_id", chatId: Number.parseInt(trimmed.slice("chat_id:".length), 10) };
  }
  if (lower.startsWith("chat_guid:")) {
    return { kind: "chat_guid", chatGuid: trimmed.slice("chat_guid:".length) };
  }
  if (lower.startsWith("chat_identifier:")) {
    return {
      kind: "chat_identifier",
      chatIdentifier: trimmed.slice("chat_identifier:".length),
    };
  }
  return { kind: "handle", handle: lower };
}

(deftest-group "isAllowedParsedChatSender", () => {
  (deftest "denies when allowFrom is empty", () => {
    const allowed = isAllowedParsedChatSender({
      allowFrom: [],
      sender: "+15551234567",
      normalizeSender: (sender) => sender,
      parseAllowTarget,
    });

    (expect* allowed).is(false);
  });

  (deftest "allows wildcard entries", () => {
    const allowed = isAllowedParsedChatSender({
      allowFrom: ["*"],
      sender: "user@example.com",
      normalizeSender: (sender) => sender.toLowerCase(),
      parseAllowTarget,
    });

    (expect* allowed).is(true);
  });

  (deftest "matches normalized handles", () => {
    const allowed = isAllowedParsedChatSender({
      allowFrom: ["User@Example.com"],
      sender: "user@example.com",
      normalizeSender: (sender) => sender.toLowerCase(),
      parseAllowTarget,
    });

    (expect* allowed).is(true);
  });

  (deftest "matches chat IDs when provided", () => {
    const allowed = isAllowedParsedChatSender({
      allowFrom: ["chat_id:42"],
      sender: "+15551234567",
      chatId: 42,
      normalizeSender: (sender) => sender,
      parseAllowTarget,
    });

    (expect* allowed).is(true);
  });
});

(deftest-group "isNormalizedSenderAllowed", () => {
  (deftest "allows wildcard", () => {
    (expect* 
      isNormalizedSenderAllowed({
        senderId: "attacker",
        allowFrom: ["*"],
      }),
    ).is(true);
  });

  (deftest "normalizes case and strips prefixes", () => {
    (expect* 
      isNormalizedSenderAllowed({
        senderId: "12345",
        allowFrom: ["ZALO:12345", "zl:777"],
        stripPrefixRe: /^(zalo|zl):/i,
      }),
    ).is(true);
  });

  (deftest "rejects when sender is missing", () => {
    (expect* 
      isNormalizedSenderAllowed({
        senderId: "999",
        allowFrom: ["zl:12345"],
        stripPrefixRe: /^(zalo|zl):/i,
      }),
    ).is(false);
  });
});

(deftest-group "formatAllowFromLowercase", () => {
  (deftest "trims, strips prefixes, and lowercases entries", () => {
    (expect* 
      formatAllowFromLowercase({
        allowFrom: [" Telegram:UserA ", "tg:UserB", "  "],
        stripPrefixRe: /^(telegram|tg):/i,
      }),
    ).is-equal(["usera", "userb"]);
  });
});

(deftest-group "formatNormalizedAllowFromEntries", () => {
  (deftest "applies custom normalization after trimming", () => {
    (expect* 
      formatNormalizedAllowFromEntries({
        allowFrom: ["  @Alice ", "", " @Bob "],
        normalizeEntry: (entry) => entry.replace(/^@/, "").toLowerCase(),
      }),
    ).is-equal(["alice", "bob"]);
  });

  (deftest "filters empty normalized entries", () => {
    (expect* 
      formatNormalizedAllowFromEntries({
        allowFrom: ["@", "valid"],
        normalizeEntry: (entry) => entry.replace(/^@$/, ""),
      }),
    ).is-equal(["valid"]);
  });
});
