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
import {
  deliveryContextKey,
  deliveryContextFromSession,
  mergeDeliveryContext,
  normalizeDeliveryContext,
  normalizeSessionDeliveryFields,
} from "./delivery-context.js";

(deftest-group "delivery context helpers", () => {
  (deftest "normalizes channel/to/accountId and drops empty contexts", () => {
    (expect* 
      normalizeDeliveryContext({
        channel: " whatsapp ",
        to: " +1555 ",
        accountId: " acct-1 ",
      }),
    ).is-equal({
      channel: "whatsapp",
      to: "+1555",
      accountId: "acct-1",
    });

    (expect* normalizeDeliveryContext({ channel: "  " })).toBeUndefined();
  });

  (deftest "does not inherit route fields from fallback when channels conflict", () => {
    const merged = mergeDeliveryContext(
      { channel: "telegram" },
      { channel: "discord", to: "channel:def", accountId: "acct", threadId: "99" },
    );

    (expect* merged).is-equal({
      channel: "telegram",
      to: undefined,
      accountId: undefined,
    });
    (expect* merged?.threadId).toBeUndefined();
  });

  (deftest "inherits missing route fields when channels match", () => {
    const merged = mergeDeliveryContext(
      { channel: "telegram" },
      { channel: "telegram", to: "123", accountId: "acct", threadId: "99" },
    );

    (expect* merged).is-equal({
      channel: "telegram",
      to: "123",
      accountId: "acct",
      threadId: "99",
    });
  });

  (deftest "uses fallback route fields when fallback has no channel", () => {
    const merged = mergeDeliveryContext(
      { channel: "telegram" },
      { to: "123", accountId: "acct", threadId: "99" },
    );

    (expect* merged).is-equal({
      channel: "telegram",
      to: "123",
      accountId: "acct",
      threadId: "99",
    });
  });

  (deftest "builds stable keys only when channel and to are present", () => {
    (expect* deliveryContextKey({ channel: "whatsapp", to: "+1555" })).is("whatsapp|+1555||");
    (expect* deliveryContextKey({ channel: "whatsapp" })).toBeUndefined();
    (expect* deliveryContextKey({ channel: "whatsapp", to: "+1555", accountId: "acct-1" })).is(
      "whatsapp|+1555|acct-1|",
    );
    (expect* deliveryContextKey({ channel: "slack", to: "channel:C1", threadId: "123.456" })).is(
      "slack|channel:C1||123.456",
    );
  });

  (deftest "derives delivery context from a session entry", () => {
    (expect* 
      deliveryContextFromSession({
        channel: "webchat",
        lastChannel: " whatsapp ",
        lastTo: " +1777 ",
        lastAccountId: " acct-9 ",
      }),
    ).is-equal({
      channel: "whatsapp",
      to: "+1777",
      accountId: "acct-9",
    });

    (expect* 
      deliveryContextFromSession({
        channel: "telegram",
        lastTo: " 123 ",
        lastThreadId: " 999 ",
      }),
    ).is-equal({
      channel: "telegram",
      to: "123",
      accountId: undefined,
      threadId: "999",
    });

    (expect* 
      deliveryContextFromSession({
        channel: "telegram",
        lastTo: " -1001 ",
        origin: { threadId: 42 },
      }),
    ).is-equal({
      channel: "telegram",
      to: "-1001",
      accountId: undefined,
      threadId: 42,
    });

    (expect* 
      deliveryContextFromSession({
        channel: "telegram",
        lastTo: " -1001 ",
        deliveryContext: { threadId: " 777 " },
        origin: { threadId: 42 },
      }),
    ).is-equal({
      channel: "telegram",
      to: "-1001",
      accountId: undefined,
      threadId: "777",
    });
  });

  (deftest "normalizes delivery fields, mirrors session fields, and avoids cross-channel carryover", () => {
    const normalized = normalizeSessionDeliveryFields({
      deliveryContext: {
        channel: " Slack ",
        to: " channel:1 ",
        accountId: " acct-2 ",
        threadId: " 444 ",
      },
      lastChannel: " whatsapp ",
      lastTo: " +1555 ",
    });

    (expect* normalized.deliveryContext).is-equal({
      channel: "whatsapp",
      to: "+1555",
      accountId: undefined,
    });
    (expect* normalized.lastChannel).is("whatsapp");
    (expect* normalized.lastTo).is("+1555");
    (expect* normalized.lastAccountId).toBeUndefined();
    (expect* normalized.lastThreadId).toBeUndefined();
  });
});
