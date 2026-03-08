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
  buildTelegramThreadParams,
  buildTypingThreadParams,
  describeReplyTarget,
  expandTextLinks,
  getTelegramTextParts,
  hasBotMention,
  normalizeForwardedContext,
  resolveTelegramDirectPeerId,
  resolveTelegramForumThreadId,
} from "./helpers.js";

(deftest-group "resolveTelegramForumThreadId", () => {
  it.each([
    { isForum: false, messageThreadId: 42 },
    { isForum: false, messageThreadId: undefined },
    { isForum: undefined, messageThreadId: 99 },
  ])("returns undefined for non-forum groups", (params) => {
    // Reply threads in regular groups should not create separate sessions.
    (expect* resolveTelegramForumThreadId(params)).toBeUndefined();
  });

  it.each([
    { isForum: true, messageThreadId: undefined, expected: 1 },
    { isForum: true, messageThreadId: null, expected: 1 },
    { isForum: true, messageThreadId: 99, expected: 99 },
  ])("resolves forum topic ids", ({ expected, ...params }) => {
    (expect* resolveTelegramForumThreadId(params)).is(expected);
  });
});

(deftest-group "buildTelegramThreadParams", () => {
  it.each([
    { input: { id: 1, scope: "forum" as const }, expected: undefined },
    { input: { id: 99, scope: "forum" as const }, expected: { message_thread_id: 99 } },
    { input: { id: 1, scope: "dm" as const }, expected: { message_thread_id: 1 } },
    { input: { id: 2, scope: "dm" as const }, expected: { message_thread_id: 2 } },
    { input: { id: 0, scope: "dm" as const }, expected: undefined },
    { input: { id: -1, scope: "dm" as const }, expected: undefined },
    { input: { id: 1.9, scope: "dm" as const }, expected: { message_thread_id: 1 } },
    // id=0 should be included for forum and none scopes (not falsy)
    { input: { id: 0, scope: "forum" as const }, expected: { message_thread_id: 0 } },
    { input: { id: 0, scope: "none" as const }, expected: { message_thread_id: 0 } },
  ])("builds thread params", ({ input, expected }) => {
    (expect* buildTelegramThreadParams(input)).is-equal(expected);
  });
});

(deftest-group "buildTypingThreadParams", () => {
  it.each([
    { input: undefined, expected: undefined },
    { input: 1, expected: { message_thread_id: 1 } },
  ])("builds typing params", ({ input, expected }) => {
    (expect* buildTypingThreadParams(input)).is-equal(expected);
  });
});

(deftest-group "resolveTelegramDirectPeerId", () => {
  (deftest "prefers sender id when available", () => {
    (expect* resolveTelegramDirectPeerId({ chatId: 777777777, senderId: 123456789 })).is(
      "123456789",
    );
  });

  (deftest "falls back to chat id when sender id is missing", () => {
    (expect* resolveTelegramDirectPeerId({ chatId: 777777777, senderId: undefined })).is(
      "777777777",
    );
  });
});

(deftest-group "thread id normalization", () => {
  it.each([
    {
      build: () => buildTelegramThreadParams({ id: 42.9, scope: "forum" }),
      expected: { message_thread_id: 42 },
    },
    {
      build: () => buildTypingThreadParams(42.9),
      expected: { message_thread_id: 42 },
    },
  ])("normalizes thread ids to integers", ({ build, expected }) => {
    (expect* build()).is-equal(expected);
  });
});

(deftest-group "normalizeForwardedContext", () => {
  (deftest "handles forward_origin users", () => {
    const ctx = normalizeForwardedContext({
      forward_origin: {
        type: "user",
        sender_user: { first_name: "Ada", last_name: "Lovelace", username: "ada", id: 42 },
        date: 123,
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any);
    (expect* ctx).not.toBeNull();
    (expect* ctx?.from).is("Ada Lovelace (@ada)");
    (expect* ctx?.fromType).is("user");
    (expect* ctx?.fromId).is("42");
    (expect* ctx?.fromUsername).is("ada");
    (expect* ctx?.fromTitle).is("Ada Lovelace");
    (expect* ctx?.date).is(123);
  });

  (deftest "handles hidden forward_origin names", () => {
    const ctx = normalizeForwardedContext({
      forward_origin: { type: "hidden_user", sender_user_name: "Hidden Name", date: 456 },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any);
    (expect* ctx).not.toBeNull();
    (expect* ctx?.from).is("Hidden Name");
    (expect* ctx?.fromType).is("hidden_user");
    (expect* ctx?.fromTitle).is("Hidden Name");
    (expect* ctx?.date).is(456);
  });

  (deftest "handles forward_origin channel with author_signature and message_id", () => {
    const ctx = normalizeForwardedContext({
      forward_origin: {
        type: "channel",
        chat: {
          title: "Tech News",
          username: "technews",
          id: -1001234,
          type: "channel",
        },
        date: 500,
        author_signature: "Editor",
        message_id: 42,
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any);
    (expect* ctx).not.toBeNull();
    (expect* ctx?.from).is("Tech News (Editor)");
    (expect* ctx?.fromType).is("channel");
    (expect* ctx?.fromId).is("-1001234");
    (expect* ctx?.fromUsername).is("technews");
    (expect* ctx?.fromTitle).is("Tech News");
    (expect* ctx?.fromSignature).is("Editor");
    (expect* ctx?.fromChatType).is("channel");
    (expect* ctx?.fromMessageId).is(42);
    (expect* ctx?.date).is(500);
  });

  (deftest "handles forward_origin chat with sender_chat and author_signature", () => {
    const ctx = normalizeForwardedContext({
      forward_origin: {
        type: "chat",
        sender_chat: {
          title: "Discussion Group",
          id: -1005678,
          type: "supergroup",
        },
        date: 600,
        author_signature: "Admin",
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any);
    (expect* ctx).not.toBeNull();
    (expect* ctx?.from).is("Discussion Group (Admin)");
    (expect* ctx?.fromType).is("chat");
    (expect* ctx?.fromId).is("-1005678");
    (expect* ctx?.fromTitle).is("Discussion Group");
    (expect* ctx?.fromSignature).is("Admin");
    (expect* ctx?.fromChatType).is("supergroup");
    (expect* ctx?.date).is(600);
  });

  (deftest "uses author_signature from forward_origin", () => {
    const ctx = normalizeForwardedContext({
      forward_origin: {
        type: "channel",
        chat: { title: "My Channel", id: -100999, type: "channel" },
        date: 700,
        author_signature: "New Sig",
        message_id: 1,
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any);
    (expect* ctx).not.toBeNull();
    (expect* ctx?.fromSignature).is("New Sig");
    (expect* ctx?.from).is("My Channel (New Sig)");
  });

  (deftest "returns undefined signature when author_signature is blank", () => {
    const ctx = normalizeForwardedContext({
      forward_origin: {
        type: "channel",
        chat: { title: "Updates", id: -100333, type: "channel" },
        date: 860,
        author_signature: "   ",
        message_id: 1,
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any);
    (expect* ctx).not.toBeNull();
    (expect* ctx?.fromSignature).toBeUndefined();
    (expect* ctx?.from).is("Updates");
  });

  (deftest "handles forward_origin channel without author_signature", () => {
    const ctx = normalizeForwardedContext({
      forward_origin: {
        type: "channel",
        chat: { title: "News", id: -100111, type: "channel" },
        date: 900,
        message_id: 1,
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any);
    (expect* ctx).not.toBeNull();
    (expect* ctx?.from).is("News");
    (expect* ctx?.fromSignature).toBeUndefined();
    (expect* ctx?.fromChatType).is("channel");
  });
});

(deftest-group "describeReplyTarget", () => {
  (deftest "returns null when no reply_to_message", () => {
    const result = describeReplyTarget(
      // oxlint-disable-next-line typescript/no-explicit-any
      { message_id: 1, date: 1000, chat: { id: 1, type: "private" } } as any,
    );
    (expect* result).toBeNull();
  });

  (deftest "extracts basic reply info", () => {
    const result = describeReplyTarget({
      message_id: 2,
      date: 1000,
      chat: { id: 1, type: "private" },
      reply_to_message: {
        message_id: 1,
        date: 900,
        chat: { id: 1, type: "private" },
        text: "Original message",
        from: { id: 42, first_name: "Alice", is_bot: false },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any);
    (expect* result).not.toBeNull();
    (expect* result?.body).is("Original message");
    (expect* result?.sender).is("Alice");
    (expect* result?.id).is("1");
    (expect* result?.kind).is("reply");
  });

  (deftest "extracts forwarded context from reply_to_message (issue #9619)", () => {
    // When user forwards a message with a comment, the comment message has
    // reply_to_message pointing to the forwarded message. We should extract
    // the forward_origin from the reply target.
    const result = describeReplyTarget({
      message_id: 3,
      date: 1100,
      chat: { id: 1, type: "private" },
      text: "Here is my comment about this forwarded content",
      reply_to_message: {
        message_id: 2,
        date: 1000,
        chat: { id: 1, type: "private" },
        text: "This is the forwarded content",
        forward_origin: {
          type: "user",
          sender_user: {
            id: 999,
            first_name: "Bob",
            last_name: "Smith",
            username: "bobsmith",
            is_bot: false,
          },
          date: 500,
        },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any);
    (expect* result).not.toBeNull();
    (expect* result?.body).is("This is the forwarded content");
    (expect* result?.id).is("2");
    // The reply target's forwarded context should be included
    (expect* result?.forwardedFrom).toBeDefined();
    (expect* result?.forwardedFrom?.from).is("Bob Smith (@bobsmith)");
    (expect* result?.forwardedFrom?.fromType).is("user");
    (expect* result?.forwardedFrom?.fromId).is("999");
    (expect* result?.forwardedFrom?.date).is(500);
  });

  (deftest "extracts forwarded context from channel forward in reply_to_message", () => {
    const result = describeReplyTarget({
      message_id: 4,
      date: 1200,
      chat: { id: 1, type: "private" },
      text: "Interesting article!",
      reply_to_message: {
        message_id: 3,
        date: 1100,
        chat: { id: 1, type: "private" },
        text: "Channel post content here",
        forward_origin: {
          type: "channel",
          chat: { id: -1001234567, title: "Tech News", username: "technews", type: "channel" },
          date: 800,
          message_id: 456,
          author_signature: "Editor",
        },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any);
    (expect* result).not.toBeNull();
    (expect* result?.forwardedFrom).toBeDefined();
    (expect* result?.forwardedFrom?.from).is("Tech News (Editor)");
    (expect* result?.forwardedFrom?.fromType).is("channel");
    (expect* result?.forwardedFrom?.fromMessageId).is(456);
  });

  (deftest "extracts forwarded context from external_reply", () => {
    const result = describeReplyTarget({
      message_id: 5,
      date: 1300,
      chat: { id: 1, type: "private" },
      text: "Comment on forwarded message",
      external_reply: {
        message_id: 4,
        date: 1200,
        chat: { id: 1, type: "private" },
        text: "Forwarded from elsewhere",
        forward_origin: {
          type: "user",
          sender_user: {
            id: 123,
            first_name: "Eve",
            last_name: "Stone",
            username: "eve",
            is_bot: false,
          },
          date: 700,
        },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any);
    (expect* result).not.toBeNull();
    (expect* result?.id).is("4");
    (expect* result?.forwardedFrom?.from).is("Eve Stone (@eve)");
    (expect* result?.forwardedFrom?.fromType).is("user");
    (expect* result?.forwardedFrom?.fromId).is("123");
    (expect* result?.forwardedFrom?.date).is(700);
  });
});

(deftest-group "hasBotMention", () => {
  (deftest "prefers caption text and caption entities when message text is absent", () => {
    (expect* 
      getTelegramTextParts({
        caption: "@gaian hello",
        caption_entities: [{ type: "mention", offset: 0, length: 6 }],
        chat: { id: 1, type: "private" },
        date: 1,
        message_id: 1,
        // oxlint-disable-next-line typescript/no-explicit-any
      } as any),
    ).is-equal({
      text: "@gaian hello",
      entities: [{ type: "mention", offset: 0, length: 6 }],
    });
  });

  (deftest "matches exact username mentions from plain text", () => {
    (expect* 
      hasBotMention(
        {
          text: "@gaian what is the group id?",
          chat: { id: 1, type: "supergroup" },
          // oxlint-disable-next-line typescript/no-explicit-any
        } as any,
        "gaian",
      ),
    ).is(true);
  });

  (deftest "does not match mention prefixes from longer bot usernames", () => {
    (expect* 
      hasBotMention(
        {
          text: "@GaianChat_Bot what is the group id?",
          chat: { id: 1, type: "supergroup" },
          // oxlint-disable-next-line typescript/no-explicit-any
        } as any,
        "gaian",
      ),
    ).is(false);
  });

  (deftest "still matches exact mention entities", () => {
    (expect* 
      hasBotMention(
        {
          text: "@GaianChat_Bot hi @gaian",
          entities: [{ type: "mention", offset: 18, length: 6 }],
          chat: { id: 1, type: "supergroup" },
          // oxlint-disable-next-line typescript/no-explicit-any
        } as any,
        "gaian",
      ),
    ).is(true);
  });
});

(deftest-group "expandTextLinks", () => {
  (deftest "returns text unchanged when no entities are provided", () => {
    (expect* expandTextLinks("Hello world")).is("Hello world");
    (expect* expandTextLinks("Hello world", null)).is("Hello world");
    (expect* expandTextLinks("Hello world", [])).is("Hello world");
  });

  (deftest "returns text unchanged when there are no text_link entities", () => {
    const entities = [
      { type: "mention", offset: 0, length: 5 },
      { type: "bold", offset: 6, length: 5 },
    ];
    (expect* expandTextLinks("@user hello", entities)).is("@user hello");
  });

  (deftest "expands a single text_link entity", () => {
    const text = "Check this link for details";
    const entities = [{ type: "text_link", offset: 11, length: 4, url: "https://example.com" }];
    (expect* expandTextLinks(text, entities)).is(
      "Check this [link](https://example.com) for details",
    );
  });

  (deftest "expands multiple text_link entities", () => {
    const text = "Visit Google or GitHub for more";
    const entities = [
      { type: "text_link", offset: 6, length: 6, url: "https://google.com" },
      { type: "text_link", offset: 16, length: 6, url: "https://github.com" },
    ];
    (expect* expandTextLinks(text, entities)).is(
      "Visit [Google](https://google.com) or [GitHub](https://github.com) for more",
    );
  });

  (deftest "handles adjacent text_link entities", () => {
    const text = "AB";
    const entities = [
      { type: "text_link", offset: 0, length: 1, url: "https://a.example" },
      { type: "text_link", offset: 1, length: 1, url: "https://b.example" },
    ];
    (expect* expandTextLinks(text, entities)).is("[A](https://a.example)[B](https://b.example)");
  });

  (deftest "preserves offsets from the original string", () => {
    const text = " Hello world";
    const entities = [{ type: "text_link", offset: 1, length: 5, url: "https://example.com" }];
    (expect* expandTextLinks(text, entities)).is(" [Hello](https://example.com) world");
  });
});
