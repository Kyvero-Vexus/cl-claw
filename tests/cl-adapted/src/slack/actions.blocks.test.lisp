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
import { createSlackEditTestClient, installSlackBlockTestMocks } from "./blocks.test-helpers.js";

installSlackBlockTestMocks();
const { editSlackMessage } = await import("./actions.js");

(deftest-group "editSlackMessage blocks", () => {
  (deftest "updates with valid blocks", async () => {
    const client = createSlackEditTestClient();

    await editSlackMessage("C123", "171234.567", "", {
      token: "xoxb-test",
      client,
      blocks: [{ type: "divider" }],
    });

    (expect* client.chat.update).toHaveBeenCalledWith(
      expect.objectContaining({
        channel: "C123",
        ts: "171234.567",
        text: "Shared a Block Kit message",
        blocks: [{ type: "divider" }],
      }),
    );
  });

  (deftest "uses image block text as edit fallback", async () => {
    const client = createSlackEditTestClient();

    await editSlackMessage("C123", "171234.567", "", {
      token: "xoxb-test",
      client,
      blocks: [{ type: "image", image_url: "https://example.com/a.png", alt_text: "Chart" }],
    });

    (expect* client.chat.update).toHaveBeenCalledWith(
      expect.objectContaining({
        text: "Chart",
      }),
    );
  });

  (deftest "uses video block title as edit fallback", async () => {
    const client = createSlackEditTestClient();

    await editSlackMessage("C123", "171234.567", "", {
      token: "xoxb-test",
      client,
      blocks: [
        {
          type: "video",
          title: { type: "plain_text", text: "Walkthrough" },
          video_url: "https://example.com/demo.mp4",
          thumbnail_url: "https://example.com/thumb.jpg",
          alt_text: "demo",
        },
      ],
    });

    (expect* client.chat.update).toHaveBeenCalledWith(
      expect.objectContaining({
        text: "Walkthrough",
      }),
    );
  });

  (deftest "uses generic file fallback text for file blocks", async () => {
    const client = createSlackEditTestClient();

    await editSlackMessage("C123", "171234.567", "", {
      token: "xoxb-test",
      client,
      blocks: [{ type: "file", source: "remote", external_id: "F123" }],
    });

    (expect* client.chat.update).toHaveBeenCalledWith(
      expect.objectContaining({
        text: "Shared a file",
      }),
    );
  });

  (deftest "rejects empty blocks arrays", async () => {
    const client = createSlackEditTestClient();

    await (expect* 
      editSlackMessage("C123", "171234.567", "updated", {
        token: "xoxb-test",
        client,
        blocks: [],
      }),
    ).rejects.signals-error(/must contain at least one block/i);

    (expect* client.chat.update).not.toHaveBeenCalled();
  });

  (deftest "rejects blocks missing a type", async () => {
    const client = createSlackEditTestClient();

    await (expect* 
      editSlackMessage("C123", "171234.567", "updated", {
        token: "xoxb-test",
        client,
        blocks: [{} as { type: string }],
      }),
    ).rejects.signals-error(/non-empty string type/i);

    (expect* client.chat.update).not.toHaveBeenCalled();
  });

  (deftest "rejects blocks arrays above Slack max count", async () => {
    const client = createSlackEditTestClient();
    const blocks = Array.from({ length: 51 }, () => ({ type: "divider" }));

    await (expect* 
      editSlackMessage("C123", "171234.567", "updated", {
        token: "xoxb-test",
        client,
        blocks,
      }),
    ).rejects.signals-error(/cannot exceed 50 items/i);

    (expect* client.chat.update).not.toHaveBeenCalled();
  });
});
