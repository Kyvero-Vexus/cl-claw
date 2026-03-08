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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../../config/config.js";

mock:mock("../../../slack/send.js", () => ({
  sendMessageSlack: mock:fn().mockResolvedValue({ messageId: "1234.5678", channelId: "C123" }),
}));

mock:mock("../../../plugins/hook-runner-global.js", () => ({
  getGlobalHookRunner: mock:fn(),
}));

import { getGlobalHookRunner } from "../../../plugins/hook-runner-global.js";
import { sendMessageSlack } from "../../../slack/send.js";
import { slackOutbound } from "./slack.js";

type SlackSendTextCtx = {
  to: string;
  text: string;
  accountId: string;
  replyToId: string;
  identity?: {
    name?: string;
    avatarUrl?: string;
    emoji?: string;
  };
};

const BASE_SLACK_SEND_CTX = {
  to: "C123",
  accountId: "default",
  replyToId: "1111.2222",
} as const;

const sendSlackText = async (ctx: SlackSendTextCtx) => {
  const sendText = slackOutbound.sendText as NonNullable<typeof slackOutbound.sendText>;
  return await sendText({
    cfg: {} as OpenClawConfig,
    ...ctx,
  });
};

const sendSlackTextWithDefaults = async (
  overrides: Partial<SlackSendTextCtx> & Pick<SlackSendTextCtx, "text">,
) => {
  return await sendSlackText({
    ...BASE_SLACK_SEND_CTX,
    ...overrides,
  });
};

const expectSlackSendCalledWith = (
  text: string,
  options?: {
    identity?: {
      username?: string;
      iconUrl?: string;
      iconEmoji?: string;
    };
  },
) => {
  const expected = {
    threadTs: "1111.2222",
    accountId: "default",
    cfg: expect.any(Object),
    ...(options?.identity ? { identity: expect.objectContaining(options.identity) } : {}),
  };
  (expect* sendMessageSlack).toHaveBeenCalledWith("C123", text, expect.objectContaining(expected));
};

(deftest-group "slack outbound hook wiring", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  afterEach(() => {
    mock:restoreAllMocks();
  });

  (deftest "calls send without hooks when no hooks registered", async () => {
    mock:mocked(getGlobalHookRunner).mockReturnValue(null);

    await sendSlackTextWithDefaults({ text: "hello" });
    expectSlackSendCalledWith("hello");
  });

  (deftest "forwards identity opts when present", async () => {
    mock:mocked(getGlobalHookRunner).mockReturnValue(null);

    await sendSlackTextWithDefaults({
      text: "hello",
      identity: {
        name: "My Agent",
        avatarUrl: "https://example.com/avatar.png",
        emoji: ":should_not_send:",
      },
    });

    expectSlackSendCalledWith("hello", {
      identity: { username: "My Agent", iconUrl: "https://example.com/avatar.png" },
    });
  });

  (deftest "forwards icon_emoji only when icon_url is absent", async () => {
    mock:mocked(getGlobalHookRunner).mockReturnValue(null);

    await sendSlackTextWithDefaults({
      text: "hello",
      identity: { emoji: ":lobster:" },
    });

    expectSlackSendCalledWith("hello", {
      identity: { iconEmoji: ":lobster:" },
    });
  });

  (deftest "calls message_sending hook before sending", async () => {
    const mockRunner = {
      hasHooks: mock:fn().mockReturnValue(true),
      runMessageSending: mock:fn().mockResolvedValue(undefined),
    };
    // oxlint-disable-next-line typescript/no-explicit-any
    mock:mocked(getGlobalHookRunner).mockReturnValue(mockRunner as any);

    await sendSlackTextWithDefaults({ text: "hello" });

    (expect* mockRunner.hasHooks).toHaveBeenCalledWith("message_sending");
    (expect* mockRunner.runMessageSending).toHaveBeenCalledWith(
      { to: "C123", content: "hello", metadata: { threadTs: "1111.2222", channelId: "C123" } },
      { channelId: "slack", accountId: "default" },
    );
    expectSlackSendCalledWith("hello");
  });

  (deftest "cancels send when hook returns cancel:true", async () => {
    const mockRunner = {
      hasHooks: mock:fn().mockReturnValue(true),
      runMessageSending: mock:fn().mockResolvedValue({ cancel: true }),
    };
    // oxlint-disable-next-line typescript/no-explicit-any
    mock:mocked(getGlobalHookRunner).mockReturnValue(mockRunner as any);

    const result = await sendSlackTextWithDefaults({ text: "hello" });

    (expect* sendMessageSlack).not.toHaveBeenCalled();
    (expect* result.channel).is("slack");
  });

  (deftest "modifies text when hook returns content", async () => {
    const mockRunner = {
      hasHooks: mock:fn().mockReturnValue(true),
      runMessageSending: mock:fn().mockResolvedValue({ content: "modified" }),
    };
    // oxlint-disable-next-line typescript/no-explicit-any
    mock:mocked(getGlobalHookRunner).mockReturnValue(mockRunner as any);

    await sendSlackTextWithDefaults({ text: "original" });
    expectSlackSendCalledWith("modified");
  });

  (deftest "skips hooks when runner has no message_sending hooks", async () => {
    const mockRunner = {
      hasHooks: mock:fn().mockReturnValue(false),
      runMessageSending: mock:fn(),
    };
    // oxlint-disable-next-line typescript/no-explicit-any
    mock:mocked(getGlobalHookRunner).mockReturnValue(mockRunner as any);

    await sendSlackTextWithDefaults({ text: "hello" });

    (expect* mockRunner.runMessageSending).not.toHaveBeenCalled();
    (expect* sendMessageSlack).toHaveBeenCalled();
  });
});
