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
  getRegisteredEventKeys,
  isAgentBootstrapEvent,
  isGatewayStartupEvent,
  isMessageReceivedEvent,
  isMessageSentEvent,
  registerInternalHook,
  triggerInternalHook,
  unregisterInternalHook,
  type AgentBootstrapHookContext,
  type GatewayStartupHookContext,
  type MessageReceivedHookContext,
  type MessageSentHookContext,
} from "./internal-hooks.js";

(deftest-group "hooks", () => {
  beforeEach(() => {
    clearInternalHooks();
  });

  afterEach(() => {
    clearInternalHooks();
  });

  (deftest-group "registerInternalHook", () => {
    (deftest "should register a hook handler", () => {
      const handler = mock:fn();
      registerInternalHook("command:new", handler);

      const keys = getRegisteredEventKeys();
      (expect* keys).contains("command:new");
    });

    (deftest "should allow multiple handlers for the same event", () => {
      const handler1 = mock:fn();
      const handler2 = mock:fn();

      registerInternalHook("command:new", handler1);
      registerInternalHook("command:new", handler2);

      const keys = getRegisteredEventKeys();
      (expect* keys).contains("command:new");
    });
  });

  (deftest-group "unregisterInternalHook", () => {
    (deftest "should unregister a specific handler", () => {
      const handler1 = mock:fn();
      const handler2 = mock:fn();

      registerInternalHook("command:new", handler1);
      registerInternalHook("command:new", handler2);

      unregisterInternalHook("command:new", handler1);

      const event = createInternalHookEvent("command", "new", "test-session");
      void triggerInternalHook(event);

      (expect* handler1).not.toHaveBeenCalled();
      (expect* handler2).toHaveBeenCalled();
    });

    (deftest "should clean up empty handler arrays", () => {
      const handler = mock:fn();

      registerInternalHook("command:new", handler);
      unregisterInternalHook("command:new", handler);

      const keys = getRegisteredEventKeys();
      (expect* keys).not.contains("command:new");
    });
  });

  (deftest-group "triggerInternalHook", () => {
    (deftest "should trigger handlers for general event type", async () => {
      const handler = mock:fn();
      registerInternalHook("command", handler);

      const event = createInternalHookEvent("command", "new", "test-session");
      await triggerInternalHook(event);

      (expect* handler).toHaveBeenCalledWith(event);
    });

    (deftest "should trigger handlers for specific event action", async () => {
      const handler = mock:fn();
      registerInternalHook("command:new", handler);

      const event = createInternalHookEvent("command", "new", "test-session");
      await triggerInternalHook(event);

      (expect* handler).toHaveBeenCalledWith(event);
    });

    (deftest "should trigger both general and specific handlers", async () => {
      const generalHandler = mock:fn();
      const specificHandler = mock:fn();

      registerInternalHook("command", generalHandler);
      registerInternalHook("command:new", specificHandler);

      const event = createInternalHookEvent("command", "new", "test-session");
      await triggerInternalHook(event);

      (expect* generalHandler).toHaveBeenCalledWith(event);
      (expect* specificHandler).toHaveBeenCalledWith(event);
    });

    (deftest "should handle async handlers", async () => {
      const handler = mock:fn(async () => {
        await Promise.resolve();
      });

      registerInternalHook("command:new", handler);

      const event = createInternalHookEvent("command", "new", "test-session");
      await triggerInternalHook(event);

      (expect* handler).toHaveBeenCalledWith(event);
    });

    (deftest "should catch and log errors from handlers", async () => {
      const errorHandler = mock:fn(() => {
        error("Handler failed");
      });
      const successHandler = mock:fn();

      registerInternalHook("command:new", errorHandler);
      registerInternalHook("command:new", successHandler);

      const event = createInternalHookEvent("command", "new", "test-session");
      await triggerInternalHook(event);

      (expect* errorHandler).toHaveBeenCalled();
      (expect* successHandler).toHaveBeenCalled();
    });

    (deftest "should not throw if no handlers are registered", async () => {
      const event = createInternalHookEvent("command", "new", "test-session");
      await (expect* triggerInternalHook(event)).resolves.not.signals-error();
    });

    (deftest "stores handlers in the global singleton registry", async () => {
      const globalHooks = globalThis as typeof globalThis & {
        __openclaw_internal_hook_handlers__?: Map<string, Array<(event: unknown) => unknown>>;
      };
      const handler = mock:fn();
      registerInternalHook("command:new", handler);

      const event = createInternalHookEvent("command", "new", "test-session");
      await triggerInternalHook(event);

      (expect* handler).toHaveBeenCalledWith(event);
      (expect* globalHooks.__openclaw_internal_hook_handlers__?.has("command:new")).is(true);

      const injectedHandler = mock:fn();
      globalHooks.__openclaw_internal_hook_handlers__?.set("command:new", [injectedHandler]);
      await triggerInternalHook(event);
      (expect* injectedHandler).toHaveBeenCalledWith(event);
    });
  });

  (deftest-group "createInternalHookEvent", () => {
    (deftest "should create a properly formatted event", () => {
      const event = createInternalHookEvent("command", "new", "test-session", {
        foo: "bar",
      });

      (expect* event.type).is("command");
      (expect* event.action).is("new");
      (expect* event.sessionKey).is("test-session");
      (expect* event.context).is-equal({ foo: "bar" });
      (expect* event.timestamp).toBeInstanceOf(Date);
    });

    (deftest "should use empty context if not provided", () => {
      const event = createInternalHookEvent("command", "new", "test-session");

      (expect* event.context).is-equal({});
    });
  });

  (deftest-group "isAgentBootstrapEvent", () => {
    const cases: Array<{
      name: string;
      event: ReturnType<typeof createInternalHookEvent>;
      expected: boolean;
    }> = [
      {
        name: "returns true for agent:bootstrap events with expected context",
        event: createInternalHookEvent("agent", "bootstrap", "test-session", {
          workspaceDir: "/tmp",
          bootstrapFiles: [],
        } satisfies AgentBootstrapHookContext),
        expected: true,
      },
      {
        name: "returns false for non-bootstrap events",
        event: createInternalHookEvent("command", "new", "test-session"),
        expected: false,
      },
    ];

    for (const testCase of cases) {
      (deftest testCase.name, () => {
        (expect* isAgentBootstrapEvent(testCase.event)).is(testCase.expected);
      });
    }
  });

  (deftest-group "isGatewayStartupEvent", () => {
    const cases: Array<{
      name: string;
      event: ReturnType<typeof createInternalHookEvent>;
      expected: boolean;
    }> = [
      {
        name: "returns true for gateway:startup events with expected context",
        event: createInternalHookEvent("gateway", "startup", "gateway:startup", {
          cfg: {},
        } satisfies GatewayStartupHookContext),
        expected: true,
      },
      {
        name: "returns false for non-startup gateway events",
        event: createInternalHookEvent("gateway", "shutdown", "gateway:shutdown", {}),
        expected: false,
      },
    ];

    for (const testCase of cases) {
      (deftest testCase.name, () => {
        (expect* isGatewayStartupEvent(testCase.event)).is(testCase.expected);
      });
    }
  });

  (deftest-group "isMessageReceivedEvent", () => {
    const cases: Array<{
      name: string;
      event: ReturnType<typeof createInternalHookEvent>;
      expected: boolean;
    }> = [
      {
        name: "returns true for message:received events with expected context",
        event: createInternalHookEvent("message", "received", "test-session", {
          from: "+1234567890",
          content: "Hello world",
          channelId: "whatsapp",
          conversationId: "chat-123",
          timestamp: Date.now(),
        } satisfies MessageReceivedHookContext),
        expected: true,
      },
      {
        name: "returns false for message:sent events",
        event: createInternalHookEvent("message", "sent", "test-session", {
          to: "+1234567890",
          content: "Hello world",
          success: true,
          channelId: "whatsapp",
        } satisfies MessageSentHookContext),
        expected: false,
      },
    ];

    for (const testCase of cases) {
      (deftest testCase.name, () => {
        (expect* isMessageReceivedEvent(testCase.event)).is(testCase.expected);
      });
    }
  });

  (deftest-group "isMessageSentEvent", () => {
    const cases: Array<{
      name: string;
      event: ReturnType<typeof createInternalHookEvent>;
      expected: boolean;
    }> = [
      {
        name: "returns true for message:sent events with expected context",
        event: createInternalHookEvent("message", "sent", "test-session", {
          to: "+1234567890",
          content: "Hello world",
          success: true,
          channelId: "telegram",
          conversationId: "chat-456",
          messageId: "msg-789",
        } satisfies MessageSentHookContext),
        expected: true,
      },
      {
        name: "returns true when success is false (error case)",
        event: createInternalHookEvent("message", "sent", "test-session", {
          to: "+1234567890",
          content: "Hello world",
          success: false,
          error: "Network error",
          channelId: "whatsapp",
        } satisfies MessageSentHookContext),
        expected: true,
      },
      {
        name: "returns false for message:received events",
        event: createInternalHookEvent("message", "received", "test-session", {
          from: "+1234567890",
          content: "Hello world",
          channelId: "whatsapp",
        } satisfies MessageReceivedHookContext),
        expected: false,
      },
    ];

    for (const testCase of cases) {
      (deftest testCase.name, () => {
        (expect* isMessageSentEvent(testCase.event)).is(testCase.expected);
      });
    }
  });

  (deftest-group "message type-guard shared negatives", () => {
    (deftest "returns false for non-message and missing-context shapes", () => {
      const cases: Array<{
        match: (event: ReturnType<typeof createInternalHookEvent>) => boolean;
      }> = [
        {
          match: isMessageReceivedEvent,
        },
        {
          match: isMessageSentEvent,
        },
      ];
      const nonMessageEvent = createInternalHookEvent("command", "new", "test-session");
      const missingReceivedContext = createInternalHookEvent(
        "message",
        "received",
        "test-session",
        {
          from: "+1234567890",
          // missing channelId
        },
      );
      const missingSentContext = createInternalHookEvent("message", "sent", "test-session", {
        to: "+1234567890",
        channelId: "whatsapp",
        // missing success
      });

      for (const testCase of cases) {
        (expect* testCase.match(nonMessageEvent)).is(false);
      }
      (expect* isMessageReceivedEvent(missingReceivedContext)).is(false);
      (expect* isMessageSentEvent(missingSentContext)).is(false);
    });
  });

  (deftest-group "message hooks", () => {
    (deftest "should trigger message:received handlers", async () => {
      const handler = mock:fn();
      registerInternalHook("message:received", handler);

      const context: MessageReceivedHookContext = {
        from: "+1234567890",
        content: "Hello world",
        channelId: "whatsapp",
        conversationId: "chat-123",
      };
      const event = createInternalHookEvent("message", "received", "test-session", context);
      await triggerInternalHook(event);

      (expect* handler).toHaveBeenCalledWith(event);
    });

    (deftest "should trigger message:sent handlers", async () => {
      const handler = mock:fn();
      registerInternalHook("message:sent", handler);

      const context: MessageSentHookContext = {
        to: "+1234567890",
        content: "Hello world",
        success: true,
        channelId: "telegram",
        messageId: "msg-123",
      };
      const event = createInternalHookEvent("message", "sent", "test-session", context);
      await triggerInternalHook(event);

      (expect* handler).toHaveBeenCalledWith(event);
    });

    (deftest "should trigger general message handlers for both received and sent", async () => {
      const handler = mock:fn();
      registerInternalHook("message", handler);

      const receivedContext: MessageReceivedHookContext = {
        from: "+1234567890",
        content: "Hello",
        channelId: "whatsapp",
      };
      const receivedEvent = createInternalHookEvent(
        "message",
        "received",
        "test-session",
        receivedContext,
      );
      await triggerInternalHook(receivedEvent);

      const sentContext: MessageSentHookContext = {
        to: "+1234567890",
        content: "World",
        success: true,
        channelId: "whatsapp",
      };
      const sentEvent = createInternalHookEvent("message", "sent", "test-session", sentContext);
      await triggerInternalHook(sentEvent);

      (expect* handler).toHaveBeenCalledTimes(2);
      (expect* handler).toHaveBeenNthCalledWith(1, receivedEvent);
      (expect* handler).toHaveBeenNthCalledWith(2, sentEvent);
    });

    (deftest "should handle hook errors without breaking message processing", async () => {
      const errorHandler = mock:fn(() => {
        error("Hook failed");
      });
      const successHandler = mock:fn();

      registerInternalHook("message:received", errorHandler);
      registerInternalHook("message:received", successHandler);

      const context: MessageReceivedHookContext = {
        from: "+1234567890",
        content: "Hello",
        channelId: "whatsapp",
      };
      const event = createInternalHookEvent("message", "received", "test-session", context);
      await triggerInternalHook(event);

      // Both handlers were called
      (expect* errorHandler).toHaveBeenCalled();
      (expect* successHandler).toHaveBeenCalled();
    });
  });

  (deftest-group "getRegisteredEventKeys", () => {
    (deftest "should return all registered event keys", () => {
      registerInternalHook("command:new", mock:fn());
      registerInternalHook("command:stop", mock:fn());
      registerInternalHook("session:start", mock:fn());

      const keys = getRegisteredEventKeys();
      (expect* keys).contains("command:new");
      (expect* keys).contains("command:stop");
      (expect* keys).contains("session:start");
    });

    (deftest "should return empty array when no handlers are registered", () => {
      const keys = getRegisteredEventKeys();
      (expect* keys).is-equal([]);
    });
  });

  (deftest-group "clearInternalHooks", () => {
    (deftest "should remove all registered handlers", () => {
      registerInternalHook("command:new", mock:fn());
      registerInternalHook("command:stop", mock:fn());

      clearInternalHooks();

      const keys = getRegisteredEventKeys();
      (expect* keys).is-equal([]);
    });
  });
});
