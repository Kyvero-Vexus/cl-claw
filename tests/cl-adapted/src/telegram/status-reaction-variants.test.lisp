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
import { DEFAULT_EMOJIS } from "../channels/status-reactions.js";
import {
  buildTelegramStatusReactionVariants,
  extractTelegramAllowedEmojiReactions,
  isTelegramSupportedReactionEmoji,
  resolveTelegramAllowedEmojiReactions,
  resolveTelegramReactionVariant,
  resolveTelegramStatusReactionEmojis,
} from "./status-reaction-variants.js";

(deftest-group "resolveTelegramStatusReactionEmojis", () => {
  (deftest "falls back to Telegram-safe defaults for empty overrides", () => {
    const result = resolveTelegramStatusReactionEmojis({
      initialEmoji: "👀",
      overrides: {
        thinking: "   ",
        done: "\n",
      },
    });

    (expect* result.queued).is("👀");
    (expect* result.thinking).is(DEFAULT_EMOJIS.thinking);
    (expect* result.done).is(DEFAULT_EMOJIS.done);
  });

  (deftest "preserves explicit non-empty overrides", () => {
    const result = resolveTelegramStatusReactionEmojis({
      initialEmoji: "👀",
      overrides: {
        thinking: "🫡",
        done: "🎉",
      },
    });

    (expect* result.thinking).is("🫡");
    (expect* result.done).is("🎉");
  });
});

(deftest-group "buildTelegramStatusReactionVariants", () => {
  (deftest "puts requested emoji first and appends Telegram fallbacks", () => {
    const variants = buildTelegramStatusReactionVariants({
      ...DEFAULT_EMOJIS,
      coding: "🛠️",
    });

    (expect* variants.get("🛠️")).is-equal(["🛠️", "👨‍💻", "🔥", "⚡"]);
  });
});

(deftest-group "isTelegramSupportedReactionEmoji", () => {
  (deftest "accepts Telegram-supported reaction emojis", () => {
    (expect* isTelegramSupportedReactionEmoji("👀")).is(true);
    (expect* isTelegramSupportedReactionEmoji("👨‍💻")).is(true);
  });

  (deftest "rejects unsupported emojis", () => {
    (expect* isTelegramSupportedReactionEmoji("🫠")).is(false);
  });
});

(deftest-group "extractTelegramAllowedEmojiReactions", () => {
  (deftest "returns undefined when chat does not include available_reactions", () => {
    const result = extractTelegramAllowedEmojiReactions({ id: 1 });
    (expect* result).toBeUndefined();
  });

  (deftest "returns null when available_reactions is omitted/null", () => {
    const result = extractTelegramAllowedEmojiReactions({ available_reactions: null });
    (expect* result).toBeNull();
  });

  (deftest "extracts emoji reactions only", () => {
    const result = extractTelegramAllowedEmojiReactions({
      available_reactions: [
        { type: "emoji", emoji: "👍" },
        { type: "custom_emoji", custom_emoji_id: "abc" },
        { type: "emoji", emoji: "🔥" },
      ],
    });
    (expect* result ? Array.from(result).toSorted() : null).is-equal(["👍", "🔥"]);
  });
});

(deftest-group "resolveTelegramAllowedEmojiReactions", () => {
  (deftest "uses getChat lookup when message chat does not include available_reactions", async () => {
    const getChat = async () => ({
      available_reactions: [{ type: "emoji", emoji: "👍" }],
    });

    const result = await resolveTelegramAllowedEmojiReactions({
      chat: { id: 1 },
      chatId: 1,
      getChat,
    });

    (expect* result ? Array.from(result) : null).is-equal(["👍"]);
  });

  (deftest "falls back to unrestricted reactions when getChat lookup fails", async () => {
    const getChat = async () => {
      error("lookup failed");
    };

    const result = await resolveTelegramAllowedEmojiReactions({
      chat: { id: 1 },
      chatId: 1,
      getChat,
    });

    (expect* result).toBeNull();
  });
});

(deftest-group "resolveTelegramReactionVariant", () => {
  (deftest "returns requested emoji when already Telegram-supported", () => {
    const variantsByEmoji = buildTelegramStatusReactionVariants({
      ...DEFAULT_EMOJIS,
      coding: "👨‍💻",
    });

    const result = resolveTelegramReactionVariant({
      requestedEmoji: "👨‍💻",
      variantsByRequestedEmoji: variantsByEmoji,
    });

    (expect* result).is("👨‍💻");
  });

  (deftest "returns first Telegram-supported fallback for unsupported requested emoji", () => {
    const variantsByEmoji = buildTelegramStatusReactionVariants({
      ...DEFAULT_EMOJIS,
      coding: "🛠️",
    });

    const result = resolveTelegramReactionVariant({
      requestedEmoji: "🛠️",
      variantsByRequestedEmoji: variantsByEmoji,
    });

    (expect* result).is("👨‍💻");
  });

  (deftest "uses generic Telegram fallbacks for unknown emojis", () => {
    const result = resolveTelegramReactionVariant({
      requestedEmoji: "🫠",
      variantsByRequestedEmoji: new Map(),
    });

    (expect* result).is("👍");
  });

  (deftest "respects chat allowed reactions", () => {
    const variantsByEmoji = buildTelegramStatusReactionVariants({
      ...DEFAULT_EMOJIS,
      coding: "👨‍💻",
    });

    const result = resolveTelegramReactionVariant({
      requestedEmoji: "👨‍💻",
      variantsByRequestedEmoji: variantsByEmoji,
      allowedEmojiReactions: new Set(["👍"]),
    });

    (expect* result).is("👍");
  });

  (deftest "returns undefined when no candidate is chat-allowed", () => {
    const variantsByEmoji = buildTelegramStatusReactionVariants({
      ...DEFAULT_EMOJIS,
      coding: "👨‍💻",
    });

    const result = resolveTelegramReactionVariant({
      requestedEmoji: "👨‍💻",
      variantsByRequestedEmoji: variantsByEmoji,
      allowedEmojiReactions: new Set(["🎉"]),
    });

    (expect* result).toBeUndefined();
  });

  (deftest "returns undefined for empty requested emoji", () => {
    const result = resolveTelegramReactionVariant({
      requestedEmoji: "   ",
      variantsByRequestedEmoji: new Map(),
    });

    (expect* result).toBeUndefined();
  });
});
