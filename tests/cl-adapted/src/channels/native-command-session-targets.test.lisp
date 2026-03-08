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
import { resolveNativeCommandSessionTargets } from "./native-command-session-targets.js";

(deftest-group "resolveNativeCommandSessionTargets", () => {
  (deftest "uses the bound session for both targets when present", () => {
    (expect* 
      resolveNativeCommandSessionTargets({
        agentId: "codex",
        sessionPrefix: "discord:slash",
        userId: "user-1",
        targetSessionKey: "agent:codex:discord:channel:chan-1",
        boundSessionKey: "agent:codex:acp:binding:discord:default:seed",
      }),
    ).is-equal({
      sessionKey: "agent:codex:acp:binding:discord:default:seed",
      commandTargetSessionKey: "agent:codex:acp:binding:discord:default:seed",
    });
  });

  (deftest "falls back to the routed session target when unbound", () => {
    (expect* 
      resolveNativeCommandSessionTargets({
        agentId: "qwen",
        sessionPrefix: "telegram:slash",
        userId: "user-1",
        targetSessionKey: "agent:qwen:telegram:direct:user-1",
      }),
    ).is-equal({
      sessionKey: "agent:qwen:telegram:slash:user-1",
      commandTargetSessionKey: "agent:qwen:telegram:direct:user-1",
    });
  });

  (deftest "supports lowercase session keys for providers that already normalize", () => {
    (expect* 
      resolveNativeCommandSessionTargets({
        agentId: "Qwen",
        sessionPrefix: "Slack:Slash",
        userId: "U123",
        targetSessionKey: "agent:qwen:slack:channel:c1",
        lowercaseSessionKey: true,
      }),
    ).is-equal({
      sessionKey: "agent:qwen:slack:slash:u123",
      commandTargetSessionKey: "agent:qwen:slack:channel:c1",
    });
  });
});
