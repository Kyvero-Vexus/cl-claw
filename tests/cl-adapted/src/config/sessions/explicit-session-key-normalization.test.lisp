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
import { normalizeExplicitSessionKey } from "./explicit-session-key-normalization.js";

function makeCtx(overrides: Partial<MsgContext>): MsgContext {
  return {
    Body: "",
    From: "",
    To: "",
    ...overrides,
  } as MsgContext;
}

(deftest-group "normalizeExplicitSessionKey", () => {
  (deftest "dispatches discord keys through the provider normalizer", () => {
    (expect* 
      normalizeExplicitSessionKey(
        "agent:fina:discord:channel:123456",
        makeCtx({
          Surface: "discord",
          ChatType: "direct",
          From: "discord:123456",
          SenderId: "123456",
        }),
      ),
    ).is("agent:fina:discord:direct:123456");
  });

  (deftest "infers the provider from From when explicit provider fields are absent", () => {
    (expect* 
      normalizeExplicitSessionKey(
        "discord:dm:123456",
        makeCtx({
          ChatType: "direct",
          From: "discord:123456",
          SenderId: "123456",
        }),
      ),
    ).is("discord:direct:123456");
  });

  (deftest "uses Provider when Surface is absent", () => {
    (expect* 
      normalizeExplicitSessionKey(
        "agent:fina:discord:dm:123456",
        makeCtx({
          Provider: "Discord",
          ChatType: "direct",
          SenderId: "123456",
        }),
      ),
    ).is("agent:fina:discord:direct:123456");
  });

  (deftest "lowercases and passes through unknown providers unchanged", () => {
    (expect* 
      normalizeExplicitSessionKey(
        "Agent:Fina:Slack:DM:ABC",
        makeCtx({
          Surface: "slack",
          From: "slack:U123",
        }),
      ),
    ).is("agent:fina:slack:dm:abc");
  });
});
