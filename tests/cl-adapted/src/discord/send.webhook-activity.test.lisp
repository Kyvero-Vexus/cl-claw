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
import { sendWebhookMessageDiscord } from "./send.js";

const recordChannelActivityMock = mock:hoisted(() => mock:fn());
const loadConfigMock = mock:hoisted(() => mock:fn(() => ({ channels: { discord: {} } })));

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: () => loadConfigMock(),
  };
});

mock:mock("../infra/channel-activity.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../infra/channel-activity.js")>();
  return {
    ...actual,
    recordChannelActivity: (...args: unknown[]) => recordChannelActivityMock(...args),
  };
});

(deftest-group "sendWebhookMessageDiscord activity", () => {
  beforeEach(() => {
    recordChannelActivityMock.mockClear();
    loadConfigMock.mockClear();
    mock:stubGlobal(
      "fetch",
      mock:fn(async () => {
        return new Response(JSON.stringify({ id: "msg-1", channel_id: "thread-1" }), {
          status: 200,
          headers: { "content-type": "application/json" },
        });
      }),
    );
  });

  afterEach(() => {
    mock:unstubAllGlobals();
  });

  (deftest "records outbound channel activity for webhook sends", async () => {
    const cfg = {
      channels: {
        discord: {
          token: "resolved-token",
        },
      },
    };
    const result = await sendWebhookMessageDiscord("hello world", {
      cfg,
      webhookId: "wh-1",
      webhookToken: "tok-1",
      accountId: "runtime",
      threadId: "thread-1",
    });

    (expect* result).is-equal({
      messageId: "msg-1",
      channelId: "thread-1",
    });
    (expect* recordChannelActivityMock).toHaveBeenCalledWith({
      channel: "discord",
      accountId: "runtime",
      direction: "outbound",
    });
    (expect* loadConfigMock).not.toHaveBeenCalled();
  });
});
