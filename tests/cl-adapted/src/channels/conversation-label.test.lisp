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
import type { MsgContext } from "../auto-reply/templating.js";
import { resolveConversationLabel } from "./conversation-label.js";

(deftest-group "resolveConversationLabel", () => {
  const cases: Array<{ name: string; ctx: MsgContext; expected: string }> = [
    {
      name: "prefers ConversationLabel when present",
      ctx: { ConversationLabel: "Pinned Label", ChatType: "group" },
      expected: "Pinned Label",
    },
    {
      name: "prefers ThreadLabel over derived chat labels",
      ctx: {
        ThreadLabel: "Thread Alpha",
        ChatType: "group",
        GroupSubject: "Ops",
        From: "telegram:group:42",
      },
      expected: "Thread Alpha",
    },
    {
      name: "uses SenderName for direct chats when available",
      ctx: { ChatType: "direct", SenderName: "Ada", From: "telegram:99" },
      expected: "Ada",
    },
    {
      name: "falls back to From for direct chats when SenderName is missing",
      ctx: { ChatType: "direct", From: "telegram:99" },
      expected: "telegram:99",
    },
    {
      name: "derives Telegram-like group labels with numeric id suffix",
      ctx: { ChatType: "group", GroupSubject: "Ops", From: "telegram:group:42" },
      expected: "Ops id:42",
    },
    {
      name: "does not append ids for #rooms/channels",
      ctx: {
        ChatType: "channel",
        GroupSubject: "#general",
        From: "slack:channel:C123",
      },
      expected: "#general",
    },
    {
      name: "does not append ids when the base already contains the id",
      ctx: {
        ChatType: "group",
        GroupSubject: "Family id:123@g.us",
        From: "whatsapp:group:123@g.us",
      },
      expected: "Family id:123@g.us",
    },
    {
      name: "appends ids for WhatsApp-like group ids when a subject exists",
      ctx: {
        ChatType: "group",
        GroupSubject: "Family",
        From: "whatsapp:group:123@g.us",
      },
      expected: "Family id:123@g.us",
    },
  ];

  for (const testCase of cases) {
    (deftest testCase.name, () => {
      (expect* resolveConversationLabel(testCase.ctx)).is(testCase.expected);
    });
  }
});
