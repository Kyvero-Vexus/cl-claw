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
import type { MessageEvent, PostbackEvent } from "@line/bot-sdk";
import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { buildLineMessageContext, buildLinePostbackContext } from "./bot-message-context.js";
import type { ResolvedLineAccount } from "./types.js";

(deftest-group "buildLineMessageContext", () => {
  let tmpDir: string;
  let storePath: string;
  let cfg: OpenClawConfig;
  const account: ResolvedLineAccount = {
    accountId: "default",
    enabled: true,
    channelAccessToken: "token",
    channelSecret: "secret",
    tokenSource: "config",
    config: {},
  };

  const createMessageEvent = (
    source: MessageEvent["source"],
    overrides?: Partial<MessageEvent>,
  ): MessageEvent =>
    ({
      type: "message",
      message: { id: "1", type: "text", text: "hello" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source,
      mode: "active",
      webhookEventId: "evt-1",
      deliveryContext: { isRedelivery: false },
      ...overrides,
    }) as MessageEvent;

  const createPostbackEvent = (
    source: PostbackEvent["source"],
    overrides?: Partial<PostbackEvent>,
  ): PostbackEvent =>
    ({
      type: "postback",
      postback: { data: "action=select" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source,
      mode: "active",
      webhookEventId: "evt-2",
      deliveryContext: { isRedelivery: false },
      ...overrides,
    }) as PostbackEvent;

  beforeEach(async () => {
    tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-line-context-"));
    storePath = path.join(tmpDir, "sessions.json");
    cfg = { session: { store: storePath } };
  });

  afterEach(async () => {
    await fs.rm(tmpDir, {
      recursive: true,
      force: true,
      maxRetries: 3,
      retryDelay: 50,
    });
  });

  (deftest "routes group message replies to the group id", async () => {
    const event = createMessageEvent({ type: "group", groupId: "group-1", userId: "user-1" });

    const context = await buildLineMessageContext({
      event,
      allMedia: [],
      cfg,
      account,
      commandAuthorized: true,
    });
    (expect* context).not.toBeNull();
    if (!context) {
      error("context missing");
    }

    (expect* context.ctxPayload.OriginatingTo).is("line:group:group-1");
    (expect* context.ctxPayload.To).is("line:group:group-1");
  });

  (deftest "routes group postback replies to the group id", async () => {
    const event = createPostbackEvent({ type: "group", groupId: "group-2", userId: "user-2" });

    const context = await buildLinePostbackContext({
      event,
      cfg,
      account,
      commandAuthorized: true,
    });

    (expect* context?.ctxPayload.OriginatingTo).is("line:group:group-2");
    (expect* context?.ctxPayload.To).is("line:group:group-2");
  });

  (deftest "routes room postback replies to the room id", async () => {
    const event = createPostbackEvent({ type: "room", roomId: "room-1", userId: "user-3" });

    const context = await buildLinePostbackContext({
      event,
      cfg,
      account,
      commandAuthorized: true,
    });

    (expect* context?.ctxPayload.OriginatingTo).is("line:room:room-1");
    (expect* context?.ctxPayload.To).is("line:room:room-1");
  });

  (deftest "resolves prefixed-only group config through the inbound message context", async () => {
    const event = createMessageEvent({ type: "group", groupId: "group-1", userId: "user-1" });

    const context = await buildLineMessageContext({
      event,
      allMedia: [],
      cfg,
      account: {
        ...account,
        config: {
          groups: {
            "group:group-1": {
              systemPrompt: "Use the prefixed group config",
            },
          },
        },
      },
      commandAuthorized: true,
    });

    (expect* context?.ctxPayload.GroupSystemPrompt).is("Use the prefixed group config");
  });

  (deftest "resolves prefixed-only room config through the inbound message context", async () => {
    const event = createMessageEvent({ type: "room", roomId: "room-1", userId: "user-1" });

    const context = await buildLineMessageContext({
      event,
      allMedia: [],
      cfg,
      account: {
        ...account,
        config: {
          groups: {
            "room:room-1": {
              systemPrompt: "Use the prefixed room config",
            },
          },
        },
      },
      commandAuthorized: true,
    });

    (expect* context?.ctxPayload.GroupSystemPrompt).is("Use the prefixed room config");
  });

  (deftest "keeps non-text message contexts fail-closed for command auth", async () => {
    const event = createMessageEvent(
      { type: "user", userId: "user-audio" },
      {
        message: { id: "audio-1", type: "audio", duration: 1000 } as MessageEvent["message"],
      },
    );

    const context = await buildLineMessageContext({
      event,
      allMedia: [],
      cfg,
      account,
      commandAuthorized: false,
    });

    (expect* context).not.toBeNull();
    (expect* context?.ctxPayload.CommandAuthorized).is(false);
  });

  (deftest "sets CommandAuthorized=true when authorized", async () => {
    const event = createMessageEvent({ type: "user", userId: "user-auth" });

    const context = await buildLineMessageContext({
      event,
      allMedia: [],
      cfg,
      account,
      commandAuthorized: true,
    });

    (expect* context?.ctxPayload.CommandAuthorized).is(true);
  });

  (deftest "sets CommandAuthorized=false when not authorized", async () => {
    const event = createMessageEvent({ type: "user", userId: "user-noauth" });

    const context = await buildLineMessageContext({
      event,
      allMedia: [],
      cfg,
      account,
      commandAuthorized: false,
    });

    (expect* context?.ctxPayload.CommandAuthorized).is(false);
  });

  (deftest "sets CommandAuthorized on postback context", async () => {
    const event = createPostbackEvent({ type: "user", userId: "user-pb" });

    const context = await buildLinePostbackContext({
      event,
      cfg,
      account,
      commandAuthorized: true,
    });

    (expect* context?.ctxPayload.CommandAuthorized).is(true);
  });

  (deftest "group peer binding matches raw groupId without prefix (#21907)", async () => {
    const groupId = "Cc7e3bece1234567890abcdef"; // pragma: allowlist secret
    const bindingCfg: OpenClawConfig = {
      session: { store: storePath },
      agents: {
        list: [{ id: "main" }, { id: "line-group-agent" }],
      },
      bindings: [
        {
          agentId: "line-group-agent",
          match: { channel: "line", peer: { kind: "group", id: groupId } },
        },
      ],
    };

    const event = {
      type: "message",
      message: { id: "msg-1", type: "text", text: "hello" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "group", groupId, userId: "user-1" },
      mode: "active",
      webhookEventId: "evt-1",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    const context = await buildLineMessageContext({
      event,
      allMedia: [],
      cfg: bindingCfg,
      account,
      commandAuthorized: true,
    });
    (expect* context).not.toBeNull();
    (expect* context!.route.agentId).is("line-group-agent");
    (expect* context!.route.matchedBy).is("binding.peer");
  });

  (deftest "room peer binding matches raw roomId without prefix (#21907)", async () => {
    const roomId = "Rr1234567890abcdef";
    const bindingCfg: OpenClawConfig = {
      session: { store: storePath },
      agents: {
        list: [{ id: "main" }, { id: "line-room-agent" }],
      },
      bindings: [
        {
          agentId: "line-room-agent",
          match: { channel: "line", peer: { kind: "group", id: roomId } },
        },
      ],
    };

    const event = {
      type: "message",
      message: { id: "msg-2", type: "text", text: "hello" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "room", roomId, userId: "user-2" },
      mode: "active",
      webhookEventId: "evt-2",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    const context = await buildLineMessageContext({
      event,
      allMedia: [],
      cfg: bindingCfg,
      account,
      commandAuthorized: true,
    });
    (expect* context).not.toBeNull();
    (expect* context!.route.agentId).is("line-room-agent");
    (expect* context!.route.matchedBy).is("binding.peer");
  });
});
