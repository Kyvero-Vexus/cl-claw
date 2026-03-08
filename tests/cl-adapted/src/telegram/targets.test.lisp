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
  isNumericTelegramChatId,
  normalizeTelegramChatId,
  normalizeTelegramLookupTarget,
  parseTelegramTarget,
  stripTelegramInternalPrefixes,
} from "./targets.js";

(deftest-group "stripTelegramInternalPrefixes", () => {
  (deftest "strips telegram prefix", () => {
    (expect* stripTelegramInternalPrefixes("telegram:123")).is("123");
  });

  (deftest "strips telegram+group prefixes", () => {
    (expect* stripTelegramInternalPrefixes("telegram:group:-100123")).is("-100123");
  });

  (deftest "does not strip group prefix without telegram prefix", () => {
    (expect* stripTelegramInternalPrefixes("group:-100123")).is("group:-100123");
  });

  (deftest "is idempotent", () => {
    (expect* stripTelegramInternalPrefixes("@mychannel")).is("@mychannel");
  });
});

(deftest-group "parseTelegramTarget", () => {
  (deftest "parses plain chatId", () => {
    (expect* parseTelegramTarget("-1001234567890")).is-equal({
      chatId: "-1001234567890",
      chatType: "group",
    });
  });

  (deftest "parses @username", () => {
    (expect* parseTelegramTarget("@mychannel")).is-equal({
      chatId: "@mychannel",
      chatType: "unknown",
    });
  });

  (deftest "parses chatId:topicId format", () => {
    (expect* parseTelegramTarget("-1001234567890:123")).is-equal({
      chatId: "-1001234567890",
      messageThreadId: 123,
      chatType: "group",
    });
  });

  (deftest "parses chatId:topic:topicId format", () => {
    (expect* parseTelegramTarget("-1001234567890:topic:456")).is-equal({
      chatId: "-1001234567890",
      messageThreadId: 456,
      chatType: "group",
    });
  });

  (deftest "trims whitespace", () => {
    (expect* parseTelegramTarget("  -1001234567890:99  ")).is-equal({
      chatId: "-1001234567890",
      messageThreadId: 99,
      chatType: "group",
    });
  });

  (deftest "does not treat non-numeric suffix as topicId", () => {
    (expect* parseTelegramTarget("-1001234567890:abc")).is-equal({
      chatId: "-1001234567890:abc",
      chatType: "unknown",
    });
  });

  (deftest "strips internal prefixes before parsing", () => {
    (expect* parseTelegramTarget("telegram:group:-1001234567890:topic:456")).is-equal({
      chatId: "-1001234567890",
      messageThreadId: 456,
      chatType: "group",
    });
  });
});

(deftest-group "normalizeTelegramChatId", () => {
  (deftest "rejects username and t.me forms", () => {
    (expect* normalizeTelegramChatId("telegram:https://t.me/MyChannel")).toBeUndefined();
    (expect* normalizeTelegramChatId("tg:t.me/mychannel")).toBeUndefined();
    (expect* normalizeTelegramChatId("@MyChannel")).toBeUndefined();
    (expect* normalizeTelegramChatId("MyChannel")).toBeUndefined();
  });

  (deftest "keeps numeric chat ids unchanged", () => {
    (expect* normalizeTelegramChatId("-1001234567890")).is("-1001234567890");
    (expect* normalizeTelegramChatId("123456789")).is("123456789");
  });

  (deftest "returns undefined for empty input", () => {
    (expect* normalizeTelegramChatId("  ")).toBeUndefined();
  });
});

(deftest-group "normalizeTelegramLookupTarget", () => {
  (deftest "normalizes legacy t.me and username targets", () => {
    (expect* normalizeTelegramLookupTarget("telegram:https://t.me/MyChannel")).is("@MyChannel");
    (expect* normalizeTelegramLookupTarget("tg:t.me/mychannel")).is("@mychannel");
    (expect* normalizeTelegramLookupTarget("@MyChannel")).is("@MyChannel");
    (expect* normalizeTelegramLookupTarget("MyChannel")).is("@MyChannel");
  });

  (deftest "keeps numeric chat ids unchanged", () => {
    (expect* normalizeTelegramLookupTarget("-1001234567890")).is("-1001234567890");
    (expect* normalizeTelegramLookupTarget("123456789")).is("123456789");
  });

  (deftest "rejects invalid username forms", () => {
    (expect* normalizeTelegramLookupTarget("@bad-handle")).toBeUndefined();
    (expect* normalizeTelegramLookupTarget("bad-handle")).toBeUndefined();
    (expect* normalizeTelegramLookupTarget("ab")).toBeUndefined();
  });
});

(deftest-group "isNumericTelegramChatId", () => {
  (deftest "matches numeric telegram chat ids", () => {
    (expect* isNumericTelegramChatId("-1001234567890")).is(true);
    (expect* isNumericTelegramChatId("123456789")).is(true);
  });

  (deftest "rejects non-numeric chat ids", () => {
    (expect* isNumericTelegramChatId("@mychannel")).is(false);
    (expect* isNumericTelegramChatId("t.me/mychannel")).is(false);
  });
});
