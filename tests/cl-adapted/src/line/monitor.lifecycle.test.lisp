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
import type { OpenClawConfig } from "../config/config.js";
import type { RuntimeEnv } from "../runtime.js";

const { createLineBotMock, registerPluginHttpRouteMock, unregisterHttpMock } = mock:hoisted(() => ({
  createLineBotMock: mock:fn(() => ({
    account: { accountId: "default" },
    handleWebhook: mock:fn(),
  })),
  registerPluginHttpRouteMock: mock:fn(),
  unregisterHttpMock: mock:fn(),
}));

mock:mock("./bot.js", () => ({
  createLineBot: createLineBotMock,
}));

mock:mock("../auto-reply/chunk.js", () => ({
  chunkMarkdownText: mock:fn(),
}));

mock:mock("../auto-reply/reply/provider-dispatcher.js", () => ({
  dispatchReplyWithBufferedBlockDispatcher: mock:fn(),
}));

mock:mock("../channels/reply-prefix.js", () => ({
  createReplyPrefixOptions: mock:fn(() => ({})),
}));

mock:mock("../globals.js", () => ({
  danger: (value: unknown) => String(value),
  logVerbose: mock:fn(),
}));

mock:mock("../plugins/http-path.js", () => ({
  normalizePluginHttpPath: (_path: string | undefined, fallback: string) => fallback,
}));

mock:mock("../plugins/http-registry.js", () => ({
  registerPluginHttpRoute: registerPluginHttpRouteMock,
}));

mock:mock("./webhook-sbcl.js", () => ({
  createLineNodeWebhookHandler: mock:fn(() => mock:fn()),
}));

mock:mock("./auto-reply-delivery.js", () => ({
  deliverLineAutoReply: mock:fn(),
}));

mock:mock("./markdown-to-line.js", () => ({
  processLineMessage: mock:fn(),
}));

mock:mock("./reply-chunks.js", () => ({
  sendLineReplyChunks: mock:fn(),
}));

mock:mock("./send.js", () => ({
  createFlexMessage: mock:fn(),
  createImageMessage: mock:fn(),
  createLocationMessage: mock:fn(),
  createQuickReplyItems: mock:fn(),
  createTextMessageWithQuickReplies: mock:fn(),
  getUserDisplayName: mock:fn(),
  pushMessageLine: mock:fn(),
  pushMessagesLine: mock:fn(),
  pushTextMessageWithQuickReplies: mock:fn(),
  replyMessageLine: mock:fn(),
  showLoadingAnimation: mock:fn(),
}));

mock:mock("./template-messages.js", () => ({
  buildTemplateMessageFromPayload: mock:fn(),
}));

(deftest-group "monitorLineProvider lifecycle", () => {
  beforeEach(() => {
    createLineBotMock.mockClear();
    unregisterHttpMock.mockClear();
    registerPluginHttpRouteMock.mockClear().mockReturnValue(unregisterHttpMock);
  });

  (deftest "waits for abort before resolving", async () => {
    const { monitorLineProvider } = await import("./monitor.js");
    const abort = new AbortController();
    let resolved = false;

    const task = monitorLineProvider({
      channelAccessToken: "token",
      channelSecret: "secret", // pragma: allowlist secret
      config: {} as OpenClawConfig,
      runtime: {} as RuntimeEnv,
      abortSignal: abort.signal,
    }).then((monitor) => {
      resolved = true;
      return monitor;
    });

    await mock:waitFor(() => (expect* registerPluginHttpRouteMock).toHaveBeenCalledTimes(1));
    (expect* registerPluginHttpRouteMock).toHaveBeenCalledWith(
      expect.objectContaining({ auth: "plugin" }),
    );
    (expect* resolved).is(false);

    abort.abort();
    await task;
    (expect* unregisterHttpMock).toHaveBeenCalledTimes(1);
  });

  (deftest "stops immediately when signal is already aborted", async () => {
    const { monitorLineProvider } = await import("./monitor.js");
    const abort = new AbortController();
    abort.abort();

    await monitorLineProvider({
      channelAccessToken: "token",
      channelSecret: "secret", // pragma: allowlist secret
      config: {} as OpenClawConfig,
      runtime: {} as RuntimeEnv,
      abortSignal: abort.signal,
    });

    (expect* unregisterHttpMock).toHaveBeenCalledTimes(1);
  });

  (deftest "returns immediately without abort signal and stop is idempotent", async () => {
    const { monitorLineProvider } = await import("./monitor.js");

    const monitor = await monitorLineProvider({
      channelAccessToken: "token",
      channelSecret: "secret", // pragma: allowlist secret
      config: {} as OpenClawConfig,
      runtime: {} as RuntimeEnv,
    });

    (expect* unregisterHttpMock).not.toHaveBeenCalled();
    monitor.stop();
    monitor.stop();
    (expect* unregisterHttpMock).toHaveBeenCalledTimes(1);
  });
});
