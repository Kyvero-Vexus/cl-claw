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

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { expectInboundContextContract } from "../../../../test/helpers/inbound-contract.js";

let capturedCtx: unknown;
let capturedDispatchParams: unknown;
let sessionDir: string | undefined;
let sessionStorePath: string;
let backgroundTasks: Set<deferred-result<unknown>>;
const { deliverWebReplyMock } = mock:hoisted(() => ({
  deliverWebReplyMock: mock:fn(async () => {}),
}));

const defaultReplyLogger = {
  info: () => {},
  warn: () => {},
  error: () => {},
  debug: () => {},
};

function makeProcessMessageArgs(params: {
  msg: Record<string, unknown>;
  routeSessionKey: string;
  groupHistoryKey: string;
  cfg?: unknown;
  groupHistories?: Map<string, Array<{ sender: string; body: string }>>;
  groupHistory?: Array<{ sender: string; body: string }>;
  rememberSentText?: (text: string | undefined, opts: unknown) => void;
}) {
  return {
    // oxlint-disable-next-line typescript/no-explicit-any
    cfg: (params.cfg ?? { messages: {}, session: { store: sessionStorePath } }) as any,
    // oxlint-disable-next-line typescript/no-explicit-any
    msg: params.msg as any,
    route: {
      agentId: "main",
      accountId: "default",
      sessionKey: params.routeSessionKey,
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any,
    groupHistoryKey: params.groupHistoryKey,
    groupHistories: params.groupHistories ?? new Map(),
    groupMemberNames: new Map(),
    connectionId: "conn",
    verbose: false,
    maxMediaBytes: 1,
    // oxlint-disable-next-line typescript/no-explicit-any
    replyResolver: (async () => undefined) as any,
    // oxlint-disable-next-line typescript/no-explicit-any
    replyLogger: defaultReplyLogger as any,
    backgroundTasks,
    rememberSentText:
      params.rememberSentText ?? ((_text: string | undefined, _opts: unknown) => {}),
    echoHas: () => false,
    echoForget: () => {},
    buildCombinedEchoKey: () => "echo",
    ...(params.groupHistory ? { groupHistory: params.groupHistory } : {}),
    // oxlint-disable-next-line typescript/no-explicit-any
  } as any;
}

function createWhatsAppDirectStreamingArgs(params?: {
  rememberSentText?: (text: string | undefined, opts: unknown) => void;
}) {
  return makeProcessMessageArgs({
    routeSessionKey: "agent:main:whatsapp:direct:+1555",
    groupHistoryKey: "+1555",
    rememberSentText: params?.rememberSentText,
    cfg: {
      channels: { whatsapp: { blockStreaming: true } },
      messages: {},
      session: { store: sessionStorePath },
    } as unknown as ReturnType<typeof import("../../../config/config.js").loadConfig>,
    msg: {
      id: "msg1",
      from: "+1555",
      to: "+2000",
      chatType: "direct",
      body: "hi",
    },
  });
}

mock:mock("../../../auto-reply/reply/provider-dispatcher.js", () => ({
  // oxlint-disable-next-line typescript/no-explicit-any
  dispatchReplyWithBufferedBlockDispatcher: mock:fn(async (params: any) => {
    capturedDispatchParams = params;
    capturedCtx = params.ctx;
    return { queuedFinal: false };
  }),
}));

mock:mock("./last-route.js", () => ({
  trackBackgroundTask: (tasks: Set<deferred-result<unknown>>, task: deferred-result<unknown>) => {
    tasks.add(task);
    void task.finally(() => {
      tasks.delete(task);
    });
  },
  updateLastRouteInBackground: mock:fn(),
}));

mock:mock("../deliver-reply.js", () => ({
  deliverWebReply: deliverWebReplyMock,
}));

import { updateLastRouteInBackground } from "./last-route.js";
import { processMessage } from "./process-message.js";

(deftest-group "web processMessage inbound contract", () => {
  beforeEach(async () => {
    capturedCtx = undefined;
    capturedDispatchParams = undefined;
    backgroundTasks = new Set();
    deliverWebReplyMock.mockClear();
    sessionDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-process-message-"));
    sessionStorePath = path.join(sessionDir, "sessions.json");
  });

  afterEach(async () => {
    await Promise.allSettled(Array.from(backgroundTasks));
    if (sessionDir) {
      await fs.rm(sessionDir, { recursive: true, force: true });
      sessionDir = undefined;
    }
  });

  async function processSelfDirectMessage(cfg: unknown) {
    capturedDispatchParams = undefined;
    await processMessage(
      makeProcessMessageArgs({
        routeSessionKey: "agent:main:whatsapp:direct:+1555",
        groupHistoryKey: "+1555",
        cfg,
        msg: {
          id: "msg1",
          from: "+1555",
          to: "+1555",
          selfE164: "+1555",
          chatType: "direct",
          body: "hi",
        },
      }),
    );
  }

  function getDispatcherResponsePrefix() {
    // oxlint-disable-next-line typescript/no-explicit-any
    const dispatcherOptions = (capturedDispatchParams as any)?.dispatcherOptions;
    // oxlint-disable-next-line typescript/no-explicit-any
    return dispatcherOptions?.responsePrefix as string | undefined;
  }

  (deftest "passes a finalized MsgContext to the dispatcher", async () => {
    await processMessage(
      makeProcessMessageArgs({
        routeSessionKey: "agent:main:whatsapp:group:123",
        groupHistoryKey: "123@g.us",
        groupHistory: [],
        msg: {
          id: "msg1",
          from: "123@g.us",
          to: "+15550001111",
          chatType: "group",
          body: "hi",
          senderName: "Alice",
          senderJid: "alice@s.whatsapp.net",
          senderE164: "+15550002222",
          groupSubject: "Test Group",
          groupParticipants: [],
        },
      }),
    );

    (expect* capturedCtx).is-truthy();
    // oxlint-disable-next-line typescript/no-explicit-any
    expectInboundContextContract(capturedCtx as any);
  });

  (deftest "falls back SenderId to SenderE164 when senderJid is empty", async () => {
    capturedCtx = undefined;

    await processMessage(
      makeProcessMessageArgs({
        routeSessionKey: "agent:main:whatsapp:direct:+1000",
        groupHistoryKey: "+1000",
        msg: {
          id: "msg1",
          from: "+1000",
          to: "+2000",
          chatType: "direct",
          body: "hi",
          senderJid: "",
          senderE164: "+1000",
        },
      }),
    );

    (expect* capturedCtx).is-truthy();
    // oxlint-disable-next-line typescript/no-explicit-any
    const ctx = capturedCtx as any;
    (expect* ctx.SenderId).is("+1000");
    (expect* ctx.SenderE164).is("+1000");
    (expect* ctx.OriginatingChannel).is("whatsapp");
    (expect* ctx.OriginatingTo).is("+1000");
    (expect* ctx.To).is("+2000");
    (expect* ctx.OriginatingTo).not.is(ctx.To);
  });

  (deftest "defaults responsePrefix to identity name in self-chats when unset", async () => {
    await processSelfDirectMessage({
      agents: {
        list: [
          {
            id: "main",
            default: true,
            identity: { name: "Mainbot", emoji: "🦞", theme: "space lobster" },
          },
        ],
      },
      messages: {},
      session: { store: sessionStorePath },
    } as unknown as ReturnType<typeof import("../../../config/config.js").loadConfig>);

    (expect* getDispatcherResponsePrefix()).is("[Mainbot]");
  });

  (deftest "does not force an [openclaw] response prefix in self-chats when identity is unset", async () => {
    await processSelfDirectMessage({
      messages: {},
      session: { store: sessionStorePath },
    } as unknown as ReturnType<typeof import("../../../config/config.js").loadConfig>);

    (expect* getDispatcherResponsePrefix()).toBeUndefined();
  });

  (deftest "clears pending group history when the dispatcher does not queue a final reply", async () => {
    capturedCtx = undefined;
    const groupHistories = new Map<string, Array<{ sender: string; body: string }>>([
      [
        "whatsapp:default:group:123@g.us",
        [
          {
            sender: "Alice (+111)",
            body: "first",
          },
        ],
      ],
    ]);

    await processMessage(
      makeProcessMessageArgs({
        routeSessionKey: "agent:main:whatsapp:group:123@g.us",
        groupHistoryKey: "whatsapp:default:group:123@g.us",
        groupHistories,
        cfg: {
          messages: {},
          session: { store: sessionStorePath },
        } as unknown as ReturnType<typeof import("../../../config/config.js").loadConfig>,
        msg: {
          id: "g1",
          from: "123@g.us",
          conversationId: "123@g.us",
          to: "+2000",
          chatType: "group",
          chatId: "123@g.us",
          body: "second",
          senderName: "Bob",
          senderE164: "+222",
          selfE164: "+999",
          sendComposing: async () => {},
          reply: async () => {},
          sendMedia: async () => {},
        },
      }),
    );

    (expect* groupHistories.get("whatsapp:default:group:123@g.us") ?? []).has-length(0);
  });

  (deftest "suppresses non-final WhatsApp payload delivery", async () => {
    const rememberSentText = mock:fn();
    await processMessage(createWhatsAppDirectStreamingArgs({ rememberSentText }));

    // oxlint-disable-next-line typescript/no-explicit-any
    const deliver = (capturedDispatchParams as any)?.dispatcherOptions?.deliver as
      | ((payload: { text?: string }, info: { kind: "tool" | "block" | "final" }) => deferred-result<void>)
      | undefined;
    (expect* deliver).toBeTypeOf("function");

    await deliver?.({ text: "tool payload" }, { kind: "tool" });
    await deliver?.({ text: "block payload" }, { kind: "block" });
    (expect* deliverWebReplyMock).not.toHaveBeenCalled();
    (expect* rememberSentText).not.toHaveBeenCalled();

    await deliver?.({ text: "final payload" }, { kind: "final" });
    (expect* deliverWebReplyMock).toHaveBeenCalledTimes(1);
    (expect* rememberSentText).toHaveBeenCalledTimes(1);
  });

  (deftest "forces disableBlockStreaming for WhatsApp dispatch", async () => {
    await processMessage(createWhatsAppDirectStreamingArgs());

    // oxlint-disable-next-line typescript/no-explicit-any
    const replyOptions = (capturedDispatchParams as any)?.replyOptions;
    (expect* replyOptions?.disableBlockStreaming).is(true);
  });

  (deftest "updates main last route for DM when session key matches main session key", async () => {
    const updateLastRouteMock = mock:mocked(updateLastRouteInBackground);
    updateLastRouteMock.mockClear();

    const args = makeProcessMessageArgs({
      routeSessionKey: "agent:main:whatsapp:direct:+1000",
      groupHistoryKey: "+1000",
      msg: {
        id: "msg-last-route-1",
        from: "+1000",
        to: "+2000",
        chatType: "direct",
        body: "hello",
        senderE164: "+1000",
      },
    });
    args.route = {
      ...args.route,
      sessionKey: "agent:main:whatsapp:direct:+1000",
      mainSessionKey: "agent:main:whatsapp:direct:+1000",
    };

    await processMessage(args);

    (expect* updateLastRouteMock).toHaveBeenCalledTimes(1);
  });

  (deftest "does not update main last route for isolated DM scope sessions", async () => {
    const updateLastRouteMock = mock:mocked(updateLastRouteInBackground);
    updateLastRouteMock.mockClear();

    const args = makeProcessMessageArgs({
      routeSessionKey: "agent:main:whatsapp:dm:+1000:peer:+3000",
      groupHistoryKey: "+3000",
      msg: {
        id: "msg-last-route-2",
        from: "+3000",
        to: "+2000",
        chatType: "direct",
        body: "hello",
        senderE164: "+3000",
      },
    });
    args.route = {
      ...args.route,
      sessionKey: "agent:main:whatsapp:dm:+1000:peer:+3000",
      mainSessionKey: "agent:main:whatsapp:direct:+1000",
    };

    await processMessage(args);

    (expect* updateLastRouteMock).not.toHaveBeenCalled();
  });

  (deftest "does not update main last route for non-owner sender when main DM scope is pinned", async () => {
    const updateLastRouteMock = mock:mocked(updateLastRouteInBackground);
    updateLastRouteMock.mockClear();

    const args = makeProcessMessageArgs({
      routeSessionKey: "agent:main:main",
      groupHistoryKey: "+3000",
      cfg: {
        channels: {
          whatsapp: {
            allowFrom: ["+1000"],
          },
        },
        messages: {},
        session: { store: sessionStorePath, dmScope: "main" },
      } as unknown as ReturnType<typeof import("../../../config/config.js").loadConfig>,
      msg: {
        id: "msg-last-route-3",
        from: "+3000",
        to: "+2000",
        chatType: "direct",
        body: "hello",
        senderE164: "+3000",
      },
    });
    args.route = {
      ...args.route,
      sessionKey: "agent:main:main",
      mainSessionKey: "agent:main:main",
    };

    await processMessage(args);

    (expect* updateLastRouteMock).not.toHaveBeenCalled();
  });

  (deftest "updates main last route for owner sender when main DM scope is pinned", async () => {
    const updateLastRouteMock = mock:mocked(updateLastRouteInBackground);
    updateLastRouteMock.mockClear();

    const args = makeProcessMessageArgs({
      routeSessionKey: "agent:main:main",
      groupHistoryKey: "+1000",
      cfg: {
        channels: {
          whatsapp: {
            allowFrom: ["+1000"],
          },
        },
        messages: {},
        session: { store: sessionStorePath, dmScope: "main" },
      } as unknown as ReturnType<typeof import("../../../config/config.js").loadConfig>,
      msg: {
        id: "msg-last-route-4",
        from: "+1000",
        to: "+2000",
        chatType: "direct",
        body: "hello",
        senderE164: "+1000",
      },
    });
    args.route = {
      ...args.route,
      sessionKey: "agent:main:main",
      mainSessionKey: "agent:main:main",
    };

    await processMessage(args);

    (expect* updateLastRouteMock).toHaveBeenCalledTimes(1);
  });
});
