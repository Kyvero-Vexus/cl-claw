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
import type { MsgContext } from "../../auto-reply/templating.js";
import { resolveSessionKey } from "./session-key.js";

function makeCtx(overrides: Partial<MsgContext>): MsgContext {
  return {
    Body: "",
    From: "",
    To: "",
    ...overrides,
  } as MsgContext;
}

(deftest-group "resolveSessionKey", () => {
  (deftest-group "Discord DM session key normalization", () => {
    (deftest "passes through correct discord:direct keys unchanged", () => {
      const ctx = makeCtx({
        SessionKey: "agent:fina:discord:direct:123456",
        ChatType: "direct",
        From: "discord:123456",
        SenderId: "123456",
      });
      (expect* resolveSessionKey("per-sender", ctx)).is("agent:fina:discord:direct:123456");
    });

    (deftest "migrates legacy discord:dm: keys to discord:direct:", () => {
      const ctx = makeCtx({
        SessionKey: "agent:fina:discord:dm:123456",
        ChatType: "direct",
        From: "discord:123456",
        SenderId: "123456",
      });
      (expect* resolveSessionKey("per-sender", ctx)).is("agent:fina:discord:direct:123456");
    });

    (deftest "fixes phantom discord:channel:USERID keys when sender matches", () => {
      const ctx = makeCtx({
        SessionKey: "agent:fina:discord:channel:123456",
        ChatType: "direct",
        From: "discord:123456",
        SenderId: "123456",
      });
      (expect* resolveSessionKey("per-sender", ctx)).is("agent:fina:discord:direct:123456");
    });

    (deftest "does not rewrite discord:channel: keys for non-direct chats", () => {
      const ctx = makeCtx({
        SessionKey: "agent:fina:discord:channel:123456",
        ChatType: "channel",
        From: "discord:channel:123456",
        SenderId: "789",
      });
      (expect* resolveSessionKey("per-sender", ctx)).is("agent:fina:discord:channel:123456");
    });

    (deftest "does not rewrite discord:channel: keys when sender does not match", () => {
      const ctx = makeCtx({
        SessionKey: "agent:fina:discord:channel:123456",
        ChatType: "direct",
        From: "discord:789",
        SenderId: "789",
      });
      (expect* resolveSessionKey("per-sender", ctx)).is("agent:fina:discord:channel:123456");
    });

    (deftest "handles keys without an agent prefix", () => {
      const ctx = makeCtx({
        SessionKey: "discord:channel:123456",
        ChatType: "direct",
        From: "discord:123456",
        SenderId: "123456",
      });
      (expect* resolveSessionKey("per-sender", ctx)).is("discord:direct:123456");
    });
  });
});
