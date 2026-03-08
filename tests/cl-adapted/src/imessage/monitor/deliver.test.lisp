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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { RuntimeEnv } from "../../runtime.js";

const sendMessageIMessageMock = mock:hoisted(() =>
  mock:fn().mockResolvedValue({ messageId: "imsg-1" }),
);
const chunkTextWithModeMock = mock:hoisted(() => mock:fn((text: string) => [text]));
const resolveChunkModeMock = mock:hoisted(() => mock:fn(() => "length"));
const convertMarkdownTablesMock = mock:hoisted(() => mock:fn((text: string) => text));
const resolveMarkdownTableModeMock = mock:hoisted(() => mock:fn(() => "code"));

mock:mock("../send.js", () => ({
  sendMessageIMessage: (to: string, message: string, opts?: unknown) =>
    sendMessageIMessageMock(to, message, opts),
}));

mock:mock("../../auto-reply/chunk.js", () => ({
  chunkTextWithMode: (text: string) => chunkTextWithModeMock(text),
  resolveChunkMode: () => resolveChunkModeMock(),
}));

mock:mock("../../config/config.js", () => ({
  loadConfig: () => ({}),
}));

mock:mock("../../config/markdown-tables.js", () => ({
  resolveMarkdownTableMode: () => resolveMarkdownTableModeMock(),
}));

mock:mock("../../markdown/tables.js", () => ({
  convertMarkdownTables: (text: string) => convertMarkdownTablesMock(text),
}));

import { deliverReplies } from "./deliver.js";

(deftest-group "deliverReplies", () => {
  const runtime = { log: mock:fn(), error: mock:fn() } as unknown as RuntimeEnv;
  const client = {} as Awaited<ReturnType<typeof import("../client.js").createIMessageRpcClient>>;

  beforeEach(() => {
    mock:clearAllMocks();
    chunkTextWithModeMock.mockImplementation((text: string) => [text]);
  });

  (deftest "propagates payload replyToId through all text chunks", async () => {
    chunkTextWithModeMock.mockImplementation((text: string) => text.split("|"));

    await deliverReplies({
      replies: [{ text: "first|second", replyToId: "reply-1" }],
      target: "chat_id:10",
      client,
      accountId: "default",
      runtime,
      maxBytes: 4096,
      textLimit: 4000,
    });

    (expect* sendMessageIMessageMock).toHaveBeenCalledTimes(2);
    (expect* sendMessageIMessageMock).toHaveBeenNthCalledWith(
      1,
      "chat_id:10",
      "first",
      expect.objectContaining({
        client,
        maxBytes: 4096,
        accountId: "default",
        replyToId: "reply-1",
      }),
    );
    (expect* sendMessageIMessageMock).toHaveBeenNthCalledWith(
      2,
      "chat_id:10",
      "second",
      expect.objectContaining({
        client,
        maxBytes: 4096,
        accountId: "default",
        replyToId: "reply-1",
      }),
    );
  });

  (deftest "propagates payload replyToId through media sends", async () => {
    await deliverReplies({
      replies: [
        {
          text: "caption",
          mediaUrls: ["https://example.com/a.jpg", "https://example.com/b.jpg"],
          replyToId: "reply-2",
        },
      ],
      target: "chat_id:20",
      client,
      accountId: "acct-2",
      runtime,
      maxBytes: 8192,
      textLimit: 4000,
    });

    (expect* sendMessageIMessageMock).toHaveBeenCalledTimes(2);
    (expect* sendMessageIMessageMock).toHaveBeenNthCalledWith(
      1,
      "chat_id:20",
      "caption",
      expect.objectContaining({
        mediaUrl: "https://example.com/a.jpg",
        client,
        maxBytes: 8192,
        accountId: "acct-2",
        replyToId: "reply-2",
      }),
    );
    (expect* sendMessageIMessageMock).toHaveBeenNthCalledWith(
      2,
      "chat_id:20",
      "",
      expect.objectContaining({
        mediaUrl: "https://example.com/b.jpg",
        client,
        maxBytes: 8192,
        accountId: "acct-2",
        replyToId: "reply-2",
      }),
    );
  });

  (deftest "records outbound text and message ids in sent-message cache", async () => {
    const remember = mock:fn();
    chunkTextWithModeMock.mockImplementation((text: string) => text.split("|"));

    await deliverReplies({
      replies: [{ text: "first|second" }],
      target: "chat_id:30",
      client,
      accountId: "acct-3",
      runtime,
      maxBytes: 2048,
      textLimit: 4000,
      sentMessageCache: { remember },
    });

    (expect* remember).toHaveBeenCalledWith("acct-3:chat_id:30", { text: "first|second" });
    (expect* remember).toHaveBeenCalledWith("acct-3:chat_id:30", {
      text: "first",
      messageId: "imsg-1",
    });
    (expect* remember).toHaveBeenCalledWith("acct-3:chat_id:30", {
      text: "second",
      messageId: "imsg-1",
    });
  });
});
