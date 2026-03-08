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
import type { SessionEntry } from "./types.js";

const storeState = mock:hoisted(() => ({
  store: {} as Record<string, SessionEntry>,
}));

mock:mock("../io.js", () => ({
  loadConfig: () => ({}),
}));

mock:mock("./paths.js", () => ({
  resolveStorePath: () => "/tmp/sessions.json",
}));

mock:mock("./store.js", () => ({
  loadSessionStore: () => storeState.store,
}));

import { extractDeliveryInfo, parseSessionThreadInfo } from "./delivery-info.js";

const buildEntry = (deliveryContext: SessionEntry["deliveryContext"]): SessionEntry => ({
  sessionId: "session-1",
  updatedAt: Date.now(),
  deliveryContext,
});

beforeEach(() => {
  storeState.store = {};
});

(deftest-group "extractDeliveryInfo", () => {
  (deftest "parses base session and thread/topic ids", () => {
    (expect* parseSessionThreadInfo("agent:main:telegram:group:1:topic:55")).is-equal({
      baseSessionKey: "agent:main:telegram:group:1",
      threadId: "55",
    });
    (expect* parseSessionThreadInfo("agent:main:slack:channel:C1:thread:123.456")).is-equal({
      baseSessionKey: "agent:main:slack:channel:C1",
      threadId: "123.456",
    });
    (expect* parseSessionThreadInfo("agent:main:telegram:dm:user-1")).is-equal({
      baseSessionKey: "agent:main:telegram:dm:user-1",
      threadId: undefined,
    });
    (expect* parseSessionThreadInfo(undefined)).is-equal({
      baseSessionKey: undefined,
      threadId: undefined,
    });
  });

  (deftest "returns deliveryContext for direct session keys", () => {
    const sessionKey = "agent:main:webchat:dm:user-123";
    storeState.store[sessionKey] = buildEntry({
      channel: "webchat",
      to: "webchat:user-123",
      accountId: "default",
    });

    const result = extractDeliveryInfo(sessionKey);

    (expect* result).is-equal({
      deliveryContext: {
        channel: "webchat",
        to: "webchat:user-123",
        accountId: "default",
      },
      threadId: undefined,
    });
  });

  (deftest "falls back to base sessions for :thread: keys", () => {
    const baseKey = "agent:main:slack:channel:C0123ABC";
    const threadKey = `${baseKey}:thread:1234567890.123456`;
    storeState.store[baseKey] = buildEntry({
      channel: "slack",
      to: "slack:C0123ABC",
      accountId: "workspace-1",
    });

    const result = extractDeliveryInfo(threadKey);

    (expect* result).is-equal({
      deliveryContext: {
        channel: "slack",
        to: "slack:C0123ABC",
        accountId: "workspace-1",
      },
      threadId: "1234567890.123456",
    });
  });

  (deftest "falls back to base sessions for :topic: keys", () => {
    const baseKey = "agent:main:telegram:group:98765";
    const topicKey = `${baseKey}:topic:55`;
    storeState.store[baseKey] = buildEntry({
      channel: "telegram",
      to: "group:98765",
      accountId: "main",
    });

    const result = extractDeliveryInfo(topicKey);

    (expect* result).is-equal({
      deliveryContext: {
        channel: "telegram",
        to: "group:98765",
        accountId: "main",
      },
      threadId: "55",
    });
  });
});
