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
  filterMessagingToolMediaDuplicates,
  shouldSuppressMessagingToolReplies,
} from "./reply-payloads.js";

(deftest-group "filterMessagingToolMediaDuplicates", () => {
  (deftest "strips mediaUrl when it matches sentMediaUrls", () => {
    const result = filterMessagingToolMediaDuplicates({
      payloads: [{ text: "hello", mediaUrl: "file:///tmp/photo.jpg" }],
      sentMediaUrls: ["file:///tmp/photo.jpg"],
    });
    (expect* result).is-equal([{ text: "hello", mediaUrl: undefined, mediaUrls: undefined }]);
  });

  (deftest "preserves mediaUrl when it is not in sentMediaUrls", () => {
    const result = filterMessagingToolMediaDuplicates({
      payloads: [{ text: "hello", mediaUrl: "file:///tmp/photo.jpg" }],
      sentMediaUrls: ["file:///tmp/other.jpg"],
    });
    (expect* result).is-equal([{ text: "hello", mediaUrl: "file:///tmp/photo.jpg" }]);
  });

  (deftest "filters matching entries from mediaUrls array", () => {
    const result = filterMessagingToolMediaDuplicates({
      payloads: [
        {
          text: "gallery",
          mediaUrls: ["file:///tmp/a.jpg", "file:///tmp/b.jpg", "file:///tmp/c.jpg"],
        },
      ],
      sentMediaUrls: ["file:///tmp/b.jpg"],
    });
    (expect* result).is-equal([
      { text: "gallery", mediaUrls: ["file:///tmp/a.jpg", "file:///tmp/c.jpg"] },
    ]);
  });

  (deftest "clears mediaUrls when all entries match", () => {
    const result = filterMessagingToolMediaDuplicates({
      payloads: [{ text: "gallery", mediaUrls: ["file:///tmp/a.jpg"] }],
      sentMediaUrls: ["file:///tmp/a.jpg"],
    });
    (expect* result).is-equal([{ text: "gallery", mediaUrl: undefined, mediaUrls: undefined }]);
  });

  (deftest "returns payloads unchanged when no media present", () => {
    const payloads = [{ text: "plain text" }];
    const result = filterMessagingToolMediaDuplicates({
      payloads,
      sentMediaUrls: ["file:///tmp/photo.jpg"],
    });
    (expect* result).toStrictEqual(payloads);
  });

  (deftest "returns payloads unchanged when sentMediaUrls is empty", () => {
    const payloads = [{ text: "hello", mediaUrl: "file:///tmp/photo.jpg" }];
    const result = filterMessagingToolMediaDuplicates({
      payloads,
      sentMediaUrls: [],
    });
    (expect* result).is(payloads);
  });

  (deftest "dedupes equivalent file and local path variants", () => {
    const result = filterMessagingToolMediaDuplicates({
      payloads: [{ text: "hello", mediaUrl: "/tmp/photo.jpg" }],
      sentMediaUrls: ["file:///tmp/photo.jpg"],
    });
    (expect* result).is-equal([{ text: "hello", mediaUrl: undefined, mediaUrls: undefined }]);
  });

  (deftest "dedupes encoded file:// paths against local paths", () => {
    const result = filterMessagingToolMediaDuplicates({
      payloads: [{ text: "hello", mediaUrl: "/tmp/photo one.jpg" }],
      sentMediaUrls: ["file:///tmp/photo%20one.jpg"],
    });
    (expect* result).is-equal([{ text: "hello", mediaUrl: undefined, mediaUrls: undefined }]);
  });
});

(deftest-group "shouldSuppressMessagingToolReplies", () => {
  (deftest "suppresses when target provider is missing but target matches current provider route", () => {
    (expect* 
      shouldSuppressMessagingToolReplies({
        messageProvider: "telegram",
        originatingTo: "123",
        messagingToolSentTargets: [{ tool: "message", provider: "", to: "123" }],
      }),
    ).is(true);
  });

  (deftest 'suppresses when target provider uses "message" placeholder and target matches', () => {
    (expect* 
      shouldSuppressMessagingToolReplies({
        messageProvider: "telegram",
        originatingTo: "123",
        messagingToolSentTargets: [{ tool: "message", provider: "message", to: "123" }],
      }),
    ).is(true);
  });

  (deftest "does not suppress when providerless target does not match origin route", () => {
    (expect* 
      shouldSuppressMessagingToolReplies({
        messageProvider: "telegram",
        originatingTo: "123",
        messagingToolSentTargets: [{ tool: "message", provider: "", to: "456" }],
      }),
    ).is(false);
  });

  (deftest "suppresses telegram topic-origin replies when explicit threadId matches", () => {
    (expect* 
      shouldSuppressMessagingToolReplies({
        messageProvider: "telegram",
        originatingTo: "telegram:group:-100123:topic:77",
        messagingToolSentTargets: [
          { tool: "message", provider: "telegram", to: "-100123", threadId: "77" },
        ],
      }),
    ).is(true);
  });

  (deftest "does not suppress telegram topic-origin replies when explicit threadId differs", () => {
    (expect* 
      shouldSuppressMessagingToolReplies({
        messageProvider: "telegram",
        originatingTo: "telegram:group:-100123:topic:77",
        messagingToolSentTargets: [
          { tool: "message", provider: "telegram", to: "-100123", threadId: "88" },
        ],
      }),
    ).is(false);
  });

  (deftest "does not suppress telegram topic-origin replies when target omits topic metadata", () => {
    (expect* 
      shouldSuppressMessagingToolReplies({
        messageProvider: "telegram",
        originatingTo: "telegram:group:-100123:topic:77",
        messagingToolSentTargets: [{ tool: "message", provider: "telegram", to: "-100123" }],
      }),
    ).is(false);
  });

  (deftest "suppresses telegram replies when chatId matches but target forms differ", () => {
    (expect* 
      shouldSuppressMessagingToolReplies({
        messageProvider: "telegram",
        originatingTo: "telegram:group:-100123",
        messagingToolSentTargets: [{ tool: "message", provider: "telegram", to: "-100123" }],
      }),
    ).is(true);
  });
});
