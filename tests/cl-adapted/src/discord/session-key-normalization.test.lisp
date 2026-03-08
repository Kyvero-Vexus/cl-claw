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
import { normalizeExplicitDiscordSessionKey } from "./session-key-normalization.js";

(deftest-group "normalizeExplicitDiscordSessionKey", () => {
  (deftest "rewrites bare discord:dm keys for direct chats", () => {
    (expect* 
      normalizeExplicitDiscordSessionKey("discord:dm:123456", {
        ChatType: "direct",
        From: "discord:123456",
        SenderId: "123456",
      }),
    ).is("discord:direct:123456");
  });

  (deftest "rewrites legacy discord:dm keys for direct chats", () => {
    (expect* 
      normalizeExplicitDiscordSessionKey("agent:fina:discord:dm:123456", {
        ChatType: "direct",
        From: "discord:123456",
        SenderId: "123456",
      }),
    ).is("agent:fina:discord:direct:123456");
  });

  (deftest "rewrites phantom discord:channel keys when sender matches", () => {
    (expect* 
      normalizeExplicitDiscordSessionKey("discord:channel:123456", {
        ChatType: "direct",
        From: "discord:123456",
        SenderId: "123456",
      }),
    ).is("discord:direct:123456");
  });

  (deftest "leaves non-direct channel keys unchanged", () => {
    (expect* 
      normalizeExplicitDiscordSessionKey("agent:fina:discord:channel:123456", {
        ChatType: "channel",
        From: "discord:channel:123456",
        SenderId: "789",
      }),
    ).is("agent:fina:discord:channel:123456");
  });
});
