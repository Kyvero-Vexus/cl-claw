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
import {
  clearInternalHooks,
  createInternalHookEvent,
  registerInternalHook,
  triggerInternalHook,
  type InternalHookEvent,
} from "./internal-hooks.js";

type ActionCase = {
  label: string;
  key: string;
  action: "received" | "transcribed" | "preprocessed" | "sent";
  context: Record<string, unknown>;
  assertContext: (context: Record<string, unknown>) => void;
};

const actionCases: ActionCase[] = [
  {
    label: "message:received",
    key: "message:received",
    action: "received",
    context: {
      from: "signal:+15551234567",
      to: "bot:+15559876543",
      content: "Test message",
      channelId: "signal",
      conversationId: "conv-abc",
      messageId: "msg-xyz",
      senderId: "sender-1",
      senderName: "Test User",
      senderUsername: "testuser",
      senderE164: "+15551234567",
      provider: "signal",
      surface: "signal",
      threadId: "thread-1",
      originatingChannel: "signal",
      originatingTo: "bot:+15559876543",
      timestamp: 1707600000,
    },
    assertContext: (context) => {
      (expect* context.content).is("Test message");
      (expect* context.channelId).is("signal");
      (expect* context.senderE164).is("+15551234567");
      (expect* context.threadId).is("thread-1");
    },
  },
  {
    label: "message:transcribed",
    key: "message:transcribed",
    action: "transcribed",
    context: {
      body: "🎤 [Audio]",
      bodyForAgent: "[Audio] Transcript: Hello from voice",
      transcript: "Hello from voice",
      channelId: "telegram",
      mediaType: "audio/ogg",
    },
    assertContext: (context) => {
      (expect* context.body).is("🎤 [Audio]");
      (expect* context.bodyForAgent).contains("Transcript:");
      (expect* context.transcript).is("Hello from voice");
      (expect* context.mediaType).is("audio/ogg");
    },
  },
  {
    label: "message:preprocessed",
    key: "message:preprocessed",
    action: "preprocessed",
    context: {
      body: "🎤 [Audio]",
      bodyForAgent: "[Audio] Transcript: Check https://example.com\n[Link summary: Example site]",
      transcript: "Check https://example.com",
      channelId: "telegram",
      mediaType: "audio/ogg",
      isGroup: false,
    },
    assertContext: (context) => {
      (expect* context.transcript).is("Check https://example.com");
      (expect* String(context.bodyForAgent)).contains("Link summary");
      (expect* String(context.bodyForAgent)).contains("Transcript:");
    },
  },
  {
    label: "message:sent",
    key: "message:sent",
    action: "sent",
    context: {
      from: "bot:456",
      to: "user:123",
      content: "Reply text",
      channelId: "discord",
      conversationId: "channel:C123",
      provider: "discord",
      surface: "discord",
      threadId: "thread-abc",
      originatingChannel: "discord",
      originatingTo: "channel:C123",
    },
    assertContext: (context) => {
      (expect* context.content).is("Reply text");
      (expect* context.channelId).is("discord");
      (expect* context.conversationId).is("channel:C123");
      (expect* context.threadId).is("thread-abc");
    },
  },
];

(deftest-group "message hooks", () => {
  beforeEach(() => {
    clearInternalHooks();
  });

  afterEach(() => {
    clearInternalHooks();
  });

  (deftest-group "action handlers", () => {
    for (const testCase of actionCases) {
      (deftest `triggers handler for ${testCase.label}`, async () => {
        const handler = mock:fn();
        registerInternalHook(testCase.key, handler);

        await triggerInternalHook(
          createInternalHookEvent("message", testCase.action, "session-1", testCase.context),
        );

        (expect* handler).toHaveBeenCalledOnce();
        const event = handler.mock.calls[0][0] as InternalHookEvent;
        (expect* event.type).is("message");
        (expect* event.action).is(testCase.action);
        testCase.assertContext(event.context);
      });
    }

    (deftest "does not trigger action-specific handlers for other actions", async () => {
      const sentHandler = mock:fn();
      registerInternalHook("message:sent", sentHandler);

      await triggerInternalHook(
        createInternalHookEvent("message", "received", "session-1", { content: "hello" }),
      );

      (expect* sentHandler).not.toHaveBeenCalled();
    });
  });

  (deftest-group "general handler", () => {
    (deftest "receives full message lifecycle in order", async () => {
      const events: InternalHookEvent[] = [];
      registerInternalHook("message", (event) => {
        events.push(event);
      });

      const lifecycleFixtures: Array<{
        action: "received" | "transcribed" | "preprocessed" | "sent";
        context: Record<string, unknown>;
      }> = [
        { action: "received", context: { content: "hi" } },
        { action: "transcribed", context: { transcript: "hello" } },
        { action: "preprocessed", context: { body: "hello", bodyForAgent: "hello" } },
        { action: "sent", context: { content: "reply" } },
      ];

      for (const fixture of lifecycleFixtures) {
        await triggerInternalHook(
          createInternalHookEvent("message", fixture.action, "s1", fixture.context),
        );
      }

      (expect* events.map((event) => event.action)).is-equal([
        "received",
        "transcribed",
        "preprocessed",
        "sent",
      ]);
    });

    (deftest "triggers both general and specific handlers", async () => {
      const generalHandler = mock:fn();
      const specificHandler = mock:fn();
      registerInternalHook("message", generalHandler);
      registerInternalHook("message:received", specificHandler);

      await triggerInternalHook(
        createInternalHookEvent("message", "received", "s1", { content: "test" }),
      );

      (expect* generalHandler).toHaveBeenCalledOnce();
      (expect* specificHandler).toHaveBeenCalledOnce();
    });
  });

  (deftest-group "error isolation", () => {
    (deftest "does not propagate handler errors", async () => {
      const badHandler = mock:fn(() => {
        error("Hook exploded");
      });
      registerInternalHook("message:received", badHandler);

      await (expect* 
        triggerInternalHook(
          createInternalHookEvent("message", "received", "s1", { content: "test" }),
        ),
      ).resolves.not.signals-error();
      (expect* badHandler).toHaveBeenCalledOnce();
    });

    (deftest "continues with later handlers when one fails", async () => {
      const failHandler = mock:fn(() => {
        error("First handler fails");
      });
      const successHandler = mock:fn();
      registerInternalHook("message:received", failHandler);
      registerInternalHook("message:received", successHandler);

      await triggerInternalHook(
        createInternalHookEvent("message", "received", "s1", { content: "test" }),
      );

      (expect* failHandler).toHaveBeenCalledOnce();
      (expect* successHandler).toHaveBeenCalledOnce();
    });

    (deftest "isolates async handler errors", async () => {
      const asyncFailHandler = mock:fn(async () => {
        error("Async hook failed");
      });
      registerInternalHook("message:sent", asyncFailHandler);

      await (expect* 
        triggerInternalHook(createInternalHookEvent("message", "sent", "s1", { content: "reply" })),
      ).resolves.not.signals-error();
      (expect* asyncFailHandler).toHaveBeenCalledOnce();
    });
  });

  (deftest-group "event structure", () => {
    (deftest "includes timestamps on message events", async () => {
      const handler = mock:fn();
      registerInternalHook("message", handler);

      const before = new Date();
      await triggerInternalHook(
        createInternalHookEvent("message", "received", "s1", { content: "hi" }),
      );
      const after = new Date();

      const event = handler.mock.calls[0][0] as InternalHookEvent;
      (expect* event.timestamp).toBeInstanceOf(Date);
      (expect* event.timestamp.getTime()).toBeGreaterThanOrEqual(before.getTime());
      (expect* event.timestamp.getTime()).toBeLessThanOrEqual(after.getTime());
    });

    (deftest "preserves mutable messages and sessionKey", async () => {
      const events: InternalHookEvent[] = [];
      registerInternalHook("message", (event) => {
        event.messages.push("Echo");
        events.push(event);
      });

      const sessionKey = "agent:main:telegram:abc";
      const received = createInternalHookEvent("message", "received", sessionKey, {
        content: "hi",
      });
      await triggerInternalHook(received);
      await triggerInternalHook(
        createInternalHookEvent("message", "sent", sessionKey, { content: "reply" }),
      );

      (expect* received.messages).contains("Echo");
      (expect* events[0]?.sessionKey).is(sessionKey);
      (expect* events[1]?.sessionKey).is(sessionKey);
    });
  });
});
