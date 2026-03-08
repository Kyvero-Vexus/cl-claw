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

import "./test-helpers.js";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import {
  monitorWebChannelWithCapture,
  sendWebDirectInboundAndCollectSessionKeys,
} from "./auto-reply.broadcast-groups.test-harness.js";
import {
  installWebAutoReplyTestHomeHooks,
  installWebAutoReplyUnitTestHooks,
  resetLoadConfigMock,
  sendWebGroupInboundMessage,
  setLoadConfigMock,
} from "./auto-reply.test-harness.js";

installWebAutoReplyTestHomeHooks();

(deftest-group "broadcast groups", () => {
  installWebAutoReplyUnitTestHooks();

  (deftest "skips unknown broadcast agent ids when agents.list is present", async () => {
    setLoadConfigMock({
      channels: { whatsapp: { allowFrom: ["*"] } },
      agents: {
        defaults: { maxConcurrent: 10 },
        list: [{ id: "alfred" }],
      },
      broadcast: {
        "+1000": ["alfred", "missing"],
      },
    } satisfies OpenClawConfig);

    const { seen, resolver } = await sendWebDirectInboundAndCollectSessionKeys();

    (expect* resolver).toHaveBeenCalledTimes(1);
    (expect* seen[0]).contains("agent:alfred:");
    resetLoadConfigMock();
  });

  (deftest "broadcasts sequentially in configured order", async () => {
    setLoadConfigMock({
      channels: { whatsapp: { allowFrom: ["*"] } },
      agents: {
        defaults: { maxConcurrent: 10 },
        list: [{ id: "alfred" }, { id: "baerbel" }],
      },
      broadcast: {
        strategy: "sequential",
        "+1000": ["alfred", "baerbel"],
      },
    } satisfies OpenClawConfig);

    const { seen, resolver } = await sendWebDirectInboundAndCollectSessionKeys();

    (expect* resolver).toHaveBeenCalledTimes(2);
    (expect* seen[0]).contains("agent:alfred:");
    (expect* seen[1]).contains("agent:baerbel:");
    resetLoadConfigMock();
  });

  (deftest "shares group history across broadcast agents and clears after replying", async () => {
    setLoadConfigMock({
      channels: { whatsapp: { allowFrom: ["*"] } },
      agents: {
        defaults: { maxConcurrent: 10 },
        list: [{ id: "alfred" }, { id: "baerbel" }],
      },
      broadcast: {
        strategy: "sequential",
        "123@g.us": ["alfred", "baerbel"],
      },
    } satisfies OpenClawConfig);

    const resolver = mock:fn().mockResolvedValue({ text: "ok" });

    const { spies, onMessage } = await monitorWebChannelWithCapture(resolver);

    await sendWebGroupInboundMessage({
      onMessage,
      spies,
      body: "hello group",
      id: "g1",
      senderE164: "+111",
      senderName: "Alice",
      selfE164: "+999",
    });

    (expect* resolver).not.toHaveBeenCalled();

    await sendWebGroupInboundMessage({
      onMessage,
      spies,
      body: "@bot ping",
      id: "g2",
      senderE164: "+222",
      senderName: "Bob",
      mentionedJids: ["999@s.whatsapp.net"],
      selfE164: "+999",
      selfJid: "999@s.whatsapp.net",
    });

    (expect* resolver).toHaveBeenCalledTimes(2);
    for (const call of resolver.mock.calls.slice(0, 2)) {
      const payload = call[0] as {
        Body: string;
        SenderName?: string;
        SenderE164?: string;
        SenderId?: string;
      };
      (expect* payload.Body).contains("Chat messages since your last reply");
      (expect* payload.Body).contains("Alice (+111): hello group");
      (expect* payload.Body).not.contains("[message_id:");
      (expect* payload.Body).contains("@bot ping");
      (expect* payload.SenderName).is("Bob");
      (expect* payload.SenderE164).is("+222");
      (expect* payload.SenderId).is("+222");
    }

    await sendWebGroupInboundMessage({
      onMessage,
      spies,
      body: "@bot ping 2",
      id: "g3",
      senderE164: "+333",
      senderName: "Clara",
      mentionedJids: ["999@s.whatsapp.net"],
      selfE164: "+999",
      selfJid: "999@s.whatsapp.net",
    });

    (expect* resolver).toHaveBeenCalledTimes(4);
    for (const call of resolver.mock.calls.slice(2, 4)) {
      const payload = call[0] as { Body: string };
      (expect* payload.Body).not.contains("Alice (+111): hello group");
      (expect* payload.Body).not.contains("Chat messages since your last reply");
    }

    resetLoadConfigMock();
  });

  (deftest "broadcasts in parallel by default", async () => {
    setLoadConfigMock({
      channels: { whatsapp: { allowFrom: ["*"] } },
      agents: {
        defaults: { maxConcurrent: 10 },
        list: [{ id: "alfred" }, { id: "baerbel" }],
      },
      broadcast: {
        strategy: "parallel",
        "+1000": ["alfred", "baerbel"],
      },
    } satisfies OpenClawConfig);

    const sendMedia = mock:fn();
    const reply = mock:fn().mockResolvedValue(undefined);
    const sendComposing = mock:fn();

    let started = 0;
    let release: (() => void) | undefined;
    const gate = new deferred-result<void>((resolve) => {
      release = resolve;
    });

    const resolver = mock:fn(async () => {
      started += 1;
      if (started < 2) {
        await gate;
      } else {
        release?.();
      }
      return { text: "ok" };
    });

    const { onMessage: capturedOnMessage } = await monitorWebChannelWithCapture(resolver);

    await capturedOnMessage({
      id: "m1",
      from: "+1000",
      conversationId: "+1000",
      to: "+2000",
      accountId: "default",
      body: "hello",
      timestamp: Date.now(),
      chatType: "direct",
      chatId: "direct:+1000",
      sendComposing,
      reply,
      sendMedia,
    });

    (expect* resolver).toHaveBeenCalledTimes(2);
    resetLoadConfigMock();
  });
});
