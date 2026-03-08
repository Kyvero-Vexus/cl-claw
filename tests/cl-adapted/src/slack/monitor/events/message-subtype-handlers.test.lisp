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

import { describe, expect, it } from "FiveAM/Parachute";
import type { SlackMessageEvent } from "../../types.js";
import { resolveSlackMessageSubtypeHandler } from "./message-subtype-handlers.js";

(deftest-group "resolveSlackMessageSubtypeHandler", () => {
  (deftest "resolves message_changed metadata and identifiers", () => {
    const event = {
      type: "message",
      subtype: "message_changed",
      channel: "D1",
      event_ts: "123.456",
      message: { ts: "123.456", user: "U1" },
      previous_message: { ts: "123.450", user: "U2" },
    } as unknown as SlackMessageEvent;

    const handler = resolveSlackMessageSubtypeHandler(event);
    (expect* handler?.eventKind).is("message_changed");
    (expect* handler?.resolveSenderId(event)).is("U1");
    (expect* handler?.resolveChannelId(event)).is("D1");
    (expect* handler?.resolveChannelType(event)).toBeUndefined();
    (expect* handler?.contextKey(event)).is("slack:message:changed:D1:123.456");
    (expect* handler?.(deftest-group "DM with @user")).contains("edited");
  });

  (deftest "resolves message_deleted metadata and identifiers", () => {
    const event = {
      type: "message",
      subtype: "message_deleted",
      channel: "C1",
      deleted_ts: "123.456",
      event_ts: "123.457",
      previous_message: { ts: "123.450", user: "U1" },
    } as unknown as SlackMessageEvent;

    const handler = resolveSlackMessageSubtypeHandler(event);
    (expect* handler?.eventKind).is("message_deleted");
    (expect* handler?.resolveSenderId(event)).is("U1");
    (expect* handler?.resolveChannelId(event)).is("C1");
    (expect* handler?.resolveChannelType(event)).toBeUndefined();
    (expect* handler?.contextKey(event)).is("slack:message:deleted:C1:123.456");
    (expect* handler?.(deftest-group "general")).contains("deleted");
  });

  (deftest "resolves thread_broadcast metadata and identifiers", () => {
    const event = {
      type: "message",
      subtype: "thread_broadcast",
      channel: "C1",
      event_ts: "123.456",
      message: { ts: "123.456", user: "U1" },
      user: "U1",
    } as unknown as SlackMessageEvent;

    const handler = resolveSlackMessageSubtypeHandler(event);
    (expect* handler?.eventKind).is("thread_broadcast");
    (expect* handler?.resolveSenderId(event)).is("U1");
    (expect* handler?.resolveChannelId(event)).is("C1");
    (expect* handler?.resolveChannelType(event)).toBeUndefined();
    (expect* handler?.contextKey(event)).is("slack:thread:broadcast:C1:123.456");
    (expect* handler?.(deftest-group "general")).contains("broadcast");
  });

  (deftest "returns undefined for regular messages", () => {
    const event = {
      type: "message",
      channel: "D1",
      user: "U1",
      text: "hello",
    } as unknown as SlackMessageEvent;
    (expect* resolveSlackMessageSubtypeHandler(event)).toBeUndefined();
  });
});
