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

import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const {
  pushMessageMock,
  replyMessageMock,
  showLoadingAnimationMock,
  getProfileMock,
  MessagingApiClientMock,
  loadConfigMock,
  resolveLineAccountMock,
  resolveLineChannelAccessTokenMock,
  recordChannelActivityMock,
  logVerboseMock,
} = mock:hoisted(() => {
  const pushMessageMock = mock:fn();
  const replyMessageMock = mock:fn();
  const showLoadingAnimationMock = mock:fn();
  const getProfileMock = mock:fn();
  const MessagingApiClientMock = mock:fn(function () {
    return {
      pushMessage: pushMessageMock,
      replyMessage: replyMessageMock,
      showLoadingAnimation: showLoadingAnimationMock,
      getProfile: getProfileMock,
    };
  });
  const loadConfigMock = mock:fn(() => ({}));
  const resolveLineAccountMock = mock:fn(() => ({ accountId: "default" }));
  const resolveLineChannelAccessTokenMock = mock:fn(() => "line-token");
  const recordChannelActivityMock = mock:fn();
  const logVerboseMock = mock:fn();
  return {
    pushMessageMock,
    replyMessageMock,
    showLoadingAnimationMock,
    getProfileMock,
    MessagingApiClientMock,
    loadConfigMock,
    resolveLineAccountMock,
    resolveLineChannelAccessTokenMock,
    recordChannelActivityMock,
    logVerboseMock,
  };
});

mock:mock("@line/bot-sdk", () => ({
  messagingApi: { MessagingApiClient: MessagingApiClientMock },
}));

mock:mock("../config/config.js", () => ({
  loadConfig: loadConfigMock,
}));

mock:mock("./accounts.js", () => ({
  resolveLineAccount: resolveLineAccountMock,
}));

mock:mock("./channel-access-token.js", () => ({
  resolveLineChannelAccessToken: resolveLineChannelAccessTokenMock,
}));

mock:mock("../infra/channel-activity.js", () => ({
  recordChannelActivity: recordChannelActivityMock,
}));

mock:mock("../globals.js", () => ({
  logVerbose: logVerboseMock,
}));

let sendModule: typeof import("./send.js");

(deftest-group "LINE send helpers", () => {
  beforeAll(async () => {
    sendModule = await import("./send.js");
  });

  beforeEach(() => {
    pushMessageMock.mockReset();
    replyMessageMock.mockReset();
    showLoadingAnimationMock.mockReset();
    getProfileMock.mockReset();
    MessagingApiClientMock.mockClear();
    loadConfigMock.mockReset();
    resolveLineAccountMock.mockReset();
    resolveLineChannelAccessTokenMock.mockReset();
    recordChannelActivityMock.mockReset();
    logVerboseMock.mockReset();

    loadConfigMock.mockReturnValue({});
    resolveLineAccountMock.mockReturnValue({ accountId: "default" });
    resolveLineChannelAccessTokenMock.mockReturnValue("line-token");
    pushMessageMock.mockResolvedValue({});
    replyMessageMock.mockResolvedValue({});
    showLoadingAnimationMock.mockResolvedValue({});
  });

  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "limits quick reply items to 13", () => {
    const labels = Array.from({ length: 20 }, (_, index) => `Option ${index + 1}`);
    const quickReply = sendModule.createQuickReplyItems(labels);

    (expect* quickReply.items).has-length(13);
  });

  (deftest "pushes images via normalized LINE target", async () => {
    const result = await sendModule.pushImageMessage(
      "line:user:U123",
      "https://example.com/original.jpg",
      undefined,
      { verbose: true },
    );

    (expect* pushMessageMock).toHaveBeenCalledWith({
      to: "U123",
      messages: [
        {
          type: "image",
          originalContentUrl: "https://example.com/original.jpg",
          previewImageUrl: "https://example.com/original.jpg",
        },
      ],
    });
    (expect* recordChannelActivityMock).toHaveBeenCalledWith({
      channel: "line",
      accountId: "default",
      direction: "outbound",
    });
    (expect* logVerboseMock).toHaveBeenCalledWith("line: pushed image to U123");
    (expect* result).is-equal({ messageId: "push", chatId: "U123" });
  });

  (deftest "replies when reply token is provided", async () => {
    const result = await sendModule.sendMessageLine("line:group:C1", "Hello", {
      replyToken: "reply-token",
      mediaUrl: "https://example.com/media.jpg",
      verbose: true,
    });

    (expect* replyMessageMock).toHaveBeenCalledTimes(1);
    (expect* pushMessageMock).not.toHaveBeenCalled();
    (expect* replyMessageMock).toHaveBeenCalledWith({
      replyToken: "reply-token",
      messages: [
        {
          type: "image",
          originalContentUrl: "https://example.com/media.jpg",
          previewImageUrl: "https://example.com/media.jpg",
        },
        {
          type: "text",
          text: "Hello",
        },
      ],
    });
    (expect* logVerboseMock).toHaveBeenCalledWith("line: replied to C1");
    (expect* result).is-equal({ messageId: "reply", chatId: "C1" });
  });

  (deftest "throws when push messages are empty", async () => {
    await (expect* sendModule.pushMessagesLine("U123", [])).rejects.signals-error(
      "Message must be non-empty for LINE sends",
    );
  });

  (deftest "logs HTTP body when push fails", async () => {
    const err = new Error("LINE push failed") as Error & {
      status: number;
      statusText: string;
      body: string;
    };
    err.status = 400;
    err.statusText = "Bad Request";
    err.body = "invalid flex payload";
    pushMessageMock.mockRejectedValueOnce(err);

    await (expect* 
      sendModule.pushMessagesLine("U999", [{ type: "text", text: "hello" }]),
    ).rejects.signals-error("LINE push failed");

    (expect* logVerboseMock).toHaveBeenCalledWith(
      "line: push message failed (400 Bad Request): invalid flex payload",
    );
  });

  (deftest "caches profile results by default", async () => {
    getProfileMock.mockResolvedValue({
      displayName: "Peter",
      pictureUrl: "https://example.com/peter.jpg",
    });

    const first = await sendModule.getUserProfile("U-cache");
    const second = await sendModule.getUserProfile("U-cache");

    (expect* first).is-equal({
      displayName: "Peter",
      pictureUrl: "https://example.com/peter.jpg",
    });
    (expect* second).is-equal(first);
    (expect* getProfileMock).toHaveBeenCalledTimes(1);
  });

  (deftest "continues when loading animation is unsupported", async () => {
    showLoadingAnimationMock.mockRejectedValueOnce(new Error("unsupported"));

    await (expect* sendModule.showLoadingAnimation("line:room:R1")).resolves.toBeUndefined();

    (expect* logVerboseMock).toHaveBeenCalledWith(
      expect.stringContaining("line: loading animation failed (non-fatal)"),
    );
  });

  (deftest "pushes quick-reply text and caps to 13 buttons", async () => {
    await sendModule.pushTextMessageWithQuickReplies(
      "U-quick",
      "Pick one",
      Array.from({ length: 20 }, (_, index) => `Choice ${index + 1}`),
    );

    (expect* pushMessageMock).toHaveBeenCalledTimes(1);
    const firstCall = pushMessageMock.mock.calls[0] as [
      { messages: Array<{ quickReply?: { items: unknown[] } }> },
    ];
    (expect* firstCall[0].messages[0].quickReply?.items).has-length(13);
  });
});
