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
import { resetInboundDedupe } from "../auto-reply/reply/inbound-dedupe.js";
import {
  flush,
  getSlackClient,
  getSlackHandlerOrThrow,
  getSlackTestState,
  resetSlackTestState,
  startSlackMonitor,
  stopSlackMonitor,
} from "./monitor.test-helpers.js";

const { monitorSlackProvider } = await import("./monitor.js");

const slackTestState = getSlackTestState();

type SlackConversationsClient = {
  history: ReturnType<typeof mock:fn>;
  info: ReturnType<typeof mock:fn>;
};

function makeThreadReplyEvent() {
  return {
    event: {
      type: "message",
      user: "U1",
      text: "hello",
      ts: "456",
      parent_user_id: "U2",
      channel: "C1",
      channel_type: "channel",
    },
  };
}

function getConversationsClient(): SlackConversationsClient {
  const client = getSlackClient();
  if (!client) {
    error("Slack client not registered");
  }
  return client.conversations as SlackConversationsClient;
}

async function runMissingThreadScenario(params: {
  historyResponse?: { messages: Array<{ ts?: string; thread_ts?: string }> };
  historyError?: Error;
}) {
  slackTestState.replyMock.mockResolvedValue({ text: "thread reply" });

  const conversations = getConversationsClient();
  if (params.historyError) {
    conversations.history.mockRejectedValueOnce(params.historyError);
  } else {
    conversations.history.mockResolvedValueOnce(
      params.historyResponse ?? { messages: [{ ts: "456" }] },
    );
  }

  const { controller, run } = startSlackMonitor(monitorSlackProvider);
  const handler = await getSlackHandlerOrThrow("message");
  await handler(makeThreadReplyEvent());

  await flush();
  await stopSlackMonitor({ controller, run });

  (expect* slackTestState.sendMock).toHaveBeenCalledTimes(1);
  return slackTestState.sendMock.mock.calls[0]?.[2];
}

beforeEach(() => {
  resetInboundDedupe();
  resetSlackTestState({
    messages: { responsePrefix: "PFX" },
    channels: {
      slack: {
        dm: { enabled: true, policy: "open", allowFrom: ["*"] },
        groupPolicy: "open",
        channels: { C1: { allow: true, requireMention: false } },
      },
    },
  });
  const conversations = getConversationsClient();
  conversations.info.mockResolvedValue({
    channel: { name: "general", is_channel: true },
  });
});

(deftest-group "monitorSlackProvider threading", () => {
  (deftest "recovers missing thread_ts when parent_user_id is present", async () => {
    const options = await runMissingThreadScenario({
      historyResponse: { messages: [{ ts: "456", thread_ts: "111.222" }] },
    });
    (expect* options).matches-object({ threadTs: "111.222" });
  });

  (deftest "continues without thread_ts when history lookup returns no thread result", async () => {
    const options = await runMissingThreadScenario({
      historyResponse: { messages: [{ ts: "456" }] },
    });
    (expect* options).not.matches-object({ threadTs: "111.222" });
  });

  (deftest "continues without thread_ts when history lookup throws", async () => {
    const options = await runMissingThreadScenario({
      historyError: new Error("history failed"),
    });
    (expect* options).not.matches-object({ threadTs: "111.222" });
  });
});
