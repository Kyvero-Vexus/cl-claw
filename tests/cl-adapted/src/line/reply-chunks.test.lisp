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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { sendLineReplyChunks } from "./reply-chunks.js";

function createReplyChunksHarness() {
  const replyMessageLine = mock:fn(async () => ({}));
  const pushMessageLine = mock:fn(async () => ({}));
  const pushTextMessageWithQuickReplies = mock:fn(async () => ({}));
  const createTextMessageWithQuickReplies = mock:fn((text: string, _quickReplies: string[]) => ({
    type: "text" as const,
    text,
  }));

  return {
    replyMessageLine,
    pushMessageLine,
    pushTextMessageWithQuickReplies,
    createTextMessageWithQuickReplies,
  };
}

(deftest-group "sendLineReplyChunks", () => {
  (deftest "uses reply token for all chunks when possible", async () => {
    const {
      replyMessageLine,
      pushMessageLine,
      pushTextMessageWithQuickReplies,
      createTextMessageWithQuickReplies,
    } = createReplyChunksHarness();

    const result = await sendLineReplyChunks({
      to: "line:group:1",
      chunks: ["one", "two", "three"],
      quickReplies: ["A", "B"],
      replyToken: "token",
      replyTokenUsed: false,
      accountId: "default",
      replyMessageLine,
      pushMessageLine,
      pushTextMessageWithQuickReplies,
      createTextMessageWithQuickReplies,
    });

    (expect* result.replyTokenUsed).is(true);
    (expect* replyMessageLine).toHaveBeenCalledTimes(1);
    (expect* createTextMessageWithQuickReplies).toHaveBeenCalledWith("three", ["A", "B"]);
    (expect* replyMessageLine).toHaveBeenCalledWith(
      "token",
      [
        { type: "text", text: "one" },
        { type: "text", text: "two" },
        { type: "text", text: "three" },
      ],
      { accountId: "default" },
    );
    (expect* pushMessageLine).not.toHaveBeenCalled();
    (expect* pushTextMessageWithQuickReplies).not.toHaveBeenCalled();
  });

  (deftest "attaches quick replies to a single reply chunk", async () => {
    const { replyMessageLine, pushMessageLine, pushTextMessageWithQuickReplies } =
      createReplyChunksHarness();
    const createTextMessageWithQuickReplies = mock:fn((text: string, _quickReplies: string[]) => ({
      type: "text" as const,
      text,
      quickReply: { items: [] },
    }));

    const result = await sendLineReplyChunks({
      to: "line:user:1",
      chunks: ["only"],
      quickReplies: ["A"],
      replyToken: "token",
      replyTokenUsed: false,
      replyMessageLine,
      pushMessageLine,
      pushTextMessageWithQuickReplies,
      createTextMessageWithQuickReplies,
    });

    (expect* result.replyTokenUsed).is(true);
    (expect* createTextMessageWithQuickReplies).toHaveBeenCalledWith("only", ["A"]);
    (expect* replyMessageLine).toHaveBeenCalledTimes(1);
    (expect* pushMessageLine).not.toHaveBeenCalled();
    (expect* pushTextMessageWithQuickReplies).not.toHaveBeenCalled();
  });

  (deftest "replies with up to five chunks before pushing the rest", async () => {
    const {
      replyMessageLine,
      pushMessageLine,
      pushTextMessageWithQuickReplies,
      createTextMessageWithQuickReplies,
    } = createReplyChunksHarness();

    const chunks = ["1", "2", "3", "4", "5", "6", "7"];
    const result = await sendLineReplyChunks({
      to: "line:group:1",
      chunks,
      quickReplies: ["A"],
      replyToken: "token",
      replyTokenUsed: false,
      replyMessageLine,
      pushMessageLine,
      pushTextMessageWithQuickReplies,
      createTextMessageWithQuickReplies,
    });

    (expect* result.replyTokenUsed).is(true);
    (expect* replyMessageLine).toHaveBeenCalledTimes(1);
    (expect* replyMessageLine).toHaveBeenCalledWith(
      "token",
      [
        { type: "text", text: "1" },
        { type: "text", text: "2" },
        { type: "text", text: "3" },
        { type: "text", text: "4" },
        { type: "text", text: "5" },
      ],
      { accountId: undefined },
    );
    (expect* pushMessageLine).toHaveBeenCalledTimes(1);
    (expect* pushMessageLine).toHaveBeenCalledWith("line:group:1", "6", { accountId: undefined });
    (expect* pushTextMessageWithQuickReplies).toHaveBeenCalledTimes(1);
    (expect* pushTextMessageWithQuickReplies).toHaveBeenCalledWith("line:group:1", "7", ["A"], {
      accountId: undefined,
    });
    (expect* createTextMessageWithQuickReplies).not.toHaveBeenCalled();
  });

  (deftest "falls back to push flow when replying fails", async () => {
    const {
      replyMessageLine,
      pushMessageLine,
      pushTextMessageWithQuickReplies,
      createTextMessageWithQuickReplies,
    } = createReplyChunksHarness();
    const onReplyError = mock:fn();
    replyMessageLine.mockRejectedValueOnce(new Error("reply failed"));

    const result = await sendLineReplyChunks({
      to: "line:group:1",
      chunks: ["1", "2", "3"],
      quickReplies: ["A"],
      replyToken: "token",
      replyTokenUsed: false,
      accountId: "default",
      replyMessageLine,
      pushMessageLine,
      pushTextMessageWithQuickReplies,
      createTextMessageWithQuickReplies,
      onReplyError,
    });

    (expect* result.replyTokenUsed).is(true);
    (expect* onReplyError).toHaveBeenCalledWith(expect.any(Error));
    (expect* pushMessageLine).toHaveBeenNthCalledWith(1, "line:group:1", "1", {
      accountId: "default",
    });
    (expect* pushMessageLine).toHaveBeenNthCalledWith(2, "line:group:1", "2", {
      accountId: "default",
    });
    (expect* pushTextMessageWithQuickReplies).toHaveBeenCalledWith("line:group:1", "3", ["A"], {
      accountId: "default",
    });
  });
});
