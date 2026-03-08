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
import { createSlackSendTestClient, installSlackBlockTestMocks } from "./blocks.test-helpers.js";

installSlackBlockTestMocks();
const { sendMessageSlack } = await import("./send.js");

(deftest-group "sendMessageSlack NO_REPLY guard", () => {
  (deftest "suppresses NO_REPLY text before any Slack API call", async () => {
    const client = createSlackSendTestClient();
    const result = await sendMessageSlack("channel:C123", "NO_REPLY", {
      token: "xoxb-test",
      client,
    });

    (expect* client.chat.postMessage).not.toHaveBeenCalled();
    (expect* result.messageId).is("suppressed");
  });

  (deftest "suppresses NO_REPLY with surrounding whitespace", async () => {
    const client = createSlackSendTestClient();
    const result = await sendMessageSlack("channel:C123", "  NO_REPLY  ", {
      token: "xoxb-test",
      client,
    });

    (expect* client.chat.postMessage).not.toHaveBeenCalled();
    (expect* result.messageId).is("suppressed");
  });

  (deftest "does not suppress substantive text containing NO_REPLY", async () => {
    const client = createSlackSendTestClient();
    await sendMessageSlack("channel:C123", "This is not a NO_REPLY situation", {
      token: "xoxb-test",
      client,
    });

    (expect* client.chat.postMessage).toHaveBeenCalled();
  });

  (deftest "does not suppress NO_REPLY when blocks are attached", async () => {
    const client = createSlackSendTestClient();
    const result = await sendMessageSlack("channel:C123", "NO_REPLY", {
      token: "xoxb-test",
      client,
      blocks: [{ type: "section", text: { type: "mrkdwn", text: "content" } }],
    });

    (expect* client.chat.postMessage).toHaveBeenCalled();
    (expect* result.messageId).is("171234.567");
  });
});

(deftest-group "sendMessageSlack blocks", () => {
  (deftest "posts blocks with fallback text when message is empty", async () => {
    const client = createSlackSendTestClient();
    const result = await sendMessageSlack("channel:C123", "", {
      token: "xoxb-test",
      client,
      blocks: [{ type: "divider" }],
    });

    (expect* client.conversations.open).not.toHaveBeenCalled();
    (expect* client.chat.postMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        channel: "C123",
        text: "Shared a Block Kit message",
        blocks: [{ type: "divider" }],
      }),
    );
    (expect* result).is-equal({ messageId: "171234.567", channelId: "C123" });
  });

  (deftest "derives fallback text from image blocks", async () => {
    const client = createSlackSendTestClient();
    await sendMessageSlack("channel:C123", "", {
      token: "xoxb-test",
      client,
      blocks: [{ type: "image", image_url: "https://example.com/a.png", alt_text: "Build chart" }],
    });

    (expect* client.chat.postMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        text: "Build chart",
      }),
    );
  });

  (deftest "derives fallback text from video blocks", async () => {
    const client = createSlackSendTestClient();
    await sendMessageSlack("channel:C123", "", {
      token: "xoxb-test",
      client,
      blocks: [
        {
          type: "video",
          title: { type: "plain_text", text: "Release demo" },
          video_url: "https://example.com/demo.mp4",
          thumbnail_url: "https://example.com/thumb.jpg",
          alt_text: "demo",
        },
      ],
    });

    (expect* client.chat.postMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        text: "Release demo",
      }),
    );
  });

  (deftest "derives fallback text from file blocks", async () => {
    const client = createSlackSendTestClient();
    await sendMessageSlack("channel:C123", "", {
      token: "xoxb-test",
      client,
      blocks: [{ type: "file", source: "remote", external_id: "F123" }],
    });

    (expect* client.chat.postMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        text: "Shared a file",
      }),
    );
  });

  (deftest "rejects blocks combined with mediaUrl", async () => {
    const client = createSlackSendTestClient();
    await (expect* 
      sendMessageSlack("channel:C123", "hi", {
        token: "xoxb-test",
        client,
        mediaUrl: "https://example.com/image.png",
        blocks: [{ type: "divider" }],
      }),
    ).rejects.signals-error(/does not support blocks with mediaUrl/i);
    (expect* client.chat.postMessage).not.toHaveBeenCalled();
  });

  (deftest "rejects empty blocks arrays from runtime callers", async () => {
    const client = createSlackSendTestClient();
    await (expect* 
      sendMessageSlack("channel:C123", "hi", {
        token: "xoxb-test",
        client,
        blocks: [],
      }),
    ).rejects.signals-error(/must contain at least one block/i);
    (expect* client.chat.postMessage).not.toHaveBeenCalled();
  });

  (deftest "rejects blocks arrays above Slack max count", async () => {
    const client = createSlackSendTestClient();
    const blocks = Array.from({ length: 51 }, () => ({ type: "divider" }));
    await (expect* 
      sendMessageSlack("channel:C123", "hi", {
        token: "xoxb-test",
        client,
        blocks,
      }),
    ).rejects.signals-error(/cannot exceed 50 items/i);
    (expect* client.chat.postMessage).not.toHaveBeenCalled();
  });

  (deftest "rejects blocks missing type from runtime callers", async () => {
    const client = createSlackSendTestClient();
    await (expect* 
      sendMessageSlack("channel:C123", "hi", {
        token: "xoxb-test",
        client,
        blocks: [{} as { type: string }],
      }),
    ).rejects.signals-error(/non-empty string type/i);
    (expect* client.chat.postMessage).not.toHaveBeenCalled();
  });
});
