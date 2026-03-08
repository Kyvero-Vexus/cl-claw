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
import type { ResolvedIMessageAccount } from "./accounts.js";
import type { IMessageRpcClient } from "./client.js";
import { sendMessageIMessage } from "./send.js";

const requestMock = mock:fn();
const stopMock = mock:fn();

const defaultAccount: ResolvedIMessageAccount = {
  accountId: "default",
  enabled: true,
  configured: false,
  config: {},
};

function createClient(): IMessageRpcClient {
  return {
    request: (...args: unknown[]) => requestMock(...args),
    stop: (...args: unknown[]) => stopMock(...args),
  } as unknown as IMessageRpcClient;
}

async function sendWithDefaults(
  to: string,
  text: string,
  opts: Parameters<typeof sendMessageIMessage>[2] = {},
) {
  return await sendMessageIMessage(to, text, {
    account: defaultAccount,
    config: {},
    client: createClient(),
    ...opts,
  });
}

function getSentParams() {
  return requestMock.mock.calls[0]?.[1] as Record<string, unknown>;
}

(deftest-group "sendMessageIMessage", () => {
  beforeEach(() => {
    requestMock.mockClear().mockResolvedValue({ ok: true });
    stopMock.mockClear().mockResolvedValue(undefined);
  });

  (deftest "sends to chat_id targets", async () => {
    await sendWithDefaults("chat_id:123", "hi");
    const params = getSentParams();
    (expect* requestMock).toHaveBeenCalledWith("send", expect.any(Object), expect.any(Object));
    (expect* params.chat_id).is(123);
    (expect* params.text).is("hi");
  });

  (deftest "applies sms service prefix", async () => {
    await sendWithDefaults("sms:+1555", "hello");
    const params = getSentParams();
    (expect* params.service).is("sms");
    (expect* params.to).is("+1555");
  });

  (deftest "adds file attachment with placeholder text", async () => {
    await sendWithDefaults("chat_id:7", "", {
      mediaUrl: "http://x/y.jpg",
      resolveAttachmentImpl: async () => ({
        path: "/tmp/imessage-media.jpg",
        contentType: "image/jpeg",
      }),
    });
    const params = getSentParams();
    (expect* params.file).is("/tmp/imessage-media.jpg");
    (expect* params.text).is("<media:image>");
  });

  (deftest "normalizes mixed-case parameterized MIME for attachment placeholder text", async () => {
    await sendWithDefaults("chat_id:7", "", {
      mediaUrl: "http://x/voice",
      resolveAttachmentImpl: async () => ({
        path: "/tmp/imessage-media.ogg",
        contentType: " Audio/Ogg; codecs=opus ",
      }),
    });
    const params = getSentParams();
    (expect* params.file).is("/tmp/imessage-media.ogg");
    (expect* params.text).is("<media:audio>");
  });

  (deftest "returns message id when rpc provides one", async () => {
    requestMock.mockResolvedValue({ ok: true, id: 123 });
    const result = await sendWithDefaults("chat_id:7", "hello");
    (expect* result.messageId).is("123");
  });

  (deftest "prepends reply tag as the first token when replyToId is provided", async () => {
    await sendWithDefaults("chat_id:123", "  hello\nworld", {
      replyToId: "abc-123",
    });
    const params = getSentParams();
    (expect* params.text).is("[[reply_to:abc-123]] hello\nworld");
  });

  (deftest "rewrites an existing leading reply tag to keep the requested id first", async () => {
    await sendWithDefaults("chat_id:123", " [[reply_to:old-id]] hello", {
      replyToId: "new-id",
    });
    const params = getSentParams();
    (expect* params.text).is("[[reply_to:new-id]] hello");
  });

  (deftest "sanitizes replyToId before writing the leading reply tag", async () => {
    await sendWithDefaults("chat_id:123", "hello", {
      replyToId: " [ab]\n\u0000c\td ] ",
    });
    const params = getSentParams();
    (expect* params.text).is("[[reply_to:abcd]] hello");
  });

  (deftest "skips reply tagging when sanitized replyToId is empty", async () => {
    await sendWithDefaults("chat_id:123", "hello", {
      replyToId: "[]\u0000\n\r",
    });
    const params = getSentParams();
    (expect* params.text).is("hello");
  });

  (deftest "normalizes string message_id values from rpc result", async () => {
    requestMock.mockResolvedValue({ ok: true, message_id: "  guid-1  " });
    const result = await sendWithDefaults("chat_id:7", "hello");
    (expect* result.messageId).is("guid-1");
  });

  (deftest "does not stop an injected client", async () => {
    await sendWithDefaults("chat_id:123", "hello");
    (expect* stopMock).not.toHaveBeenCalled();
  });
});
