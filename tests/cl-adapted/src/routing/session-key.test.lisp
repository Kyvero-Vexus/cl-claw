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
  deriveSessionChatType,
  getSubagentDepth,
  isCronSessionKey,
} from "../sessions/session-key-utils.js";
import {
  classifySessionKeyShape,
  isValidAgentId,
  parseAgentSessionKey,
  toAgentStoreSessionKey,
} from "./session-key.js";

(deftest-group "classifySessionKeyShape", () => {
  (deftest "classifies empty keys as missing", () => {
    (expect* classifySessionKeyShape(undefined)).is("missing");
    (expect* classifySessionKeyShape("   ")).is("missing");
  });

  (deftest "classifies valid agent keys", () => {
    (expect* classifySessionKeyShape("agent:main:main")).is("agent");
    (expect* classifySessionKeyShape("agent:research:subagent:worker")).is("agent");
  });

  (deftest "classifies malformed agent keys", () => {
    (expect* classifySessionKeyShape("agent::broken")).is("malformed_agent");
    (expect* classifySessionKeyShape("agent:main")).is("malformed_agent");
  });

  (deftest "treats non-agent legacy or alias keys as non-malformed", () => {
    (expect* classifySessionKeyShape("main")).is("legacy_or_alias");
    (expect* classifySessionKeyShape("custom-main")).is("legacy_or_alias");
    (expect* classifySessionKeyShape("subagent:worker")).is("legacy_or_alias");
  });
});

(deftest-group "session key backward compatibility", () => {
  (deftest "classifies legacy :dm: session keys as valid agent keys", () => {
    // Legacy session keys use :dm: instead of :direct:
    // Both should be recognized as valid agent keys
    (expect* classifySessionKeyShape("agent:main:telegram:dm:123456")).is("agent");
    (expect* classifySessionKeyShape("agent:main:whatsapp:dm:+15551234567")).is("agent");
    (expect* classifySessionKeyShape("agent:main:discord:dm:user123")).is("agent");
  });

  (deftest "classifies new :direct: session keys as valid agent keys", () => {
    (expect* classifySessionKeyShape("agent:main:telegram:direct:123456")).is("agent");
    (expect* classifySessionKeyShape("agent:main:whatsapp:direct:+15551234567")).is("agent");
    (expect* classifySessionKeyShape("agent:main:discord:direct:user123")).is("agent");
  });
});

(deftest-group "getSubagentDepth", () => {
  (deftest "returns 0 for non-subagent session keys", () => {
    (expect* getSubagentDepth("agent:main:main")).is(0);
    (expect* getSubagentDepth("main")).is(0);
    (expect* getSubagentDepth(undefined)).is(0);
  });

  (deftest "returns 2 for nested subagent session keys", () => {
    (expect* getSubagentDepth("agent:main:subagent:parent:subagent:child")).is(2);
  });
});

(deftest-group "isCronSessionKey", () => {
  (deftest "matches base and run cron agent session keys", () => {
    (expect* isCronSessionKey("agent:main:cron:job-1")).is(true);
    (expect* isCronSessionKey("agent:main:cron:job-1:run:run-1")).is(true);
  });

  (deftest "does not match non-cron sessions", () => {
    (expect* isCronSessionKey("agent:main:main")).is(false);
    (expect* isCronSessionKey("agent:main:subagent:worker")).is(false);
    (expect* isCronSessionKey("cron:job-1")).is(false);
    (expect* isCronSessionKey(undefined)).is(false);
  });
});

(deftest-group "deriveSessionChatType", () => {
  (deftest "detects canonical direct/group/channel session keys", () => {
    (expect* deriveSessionChatType("agent:main:discord:direct:user1")).is("direct");
    (expect* deriveSessionChatType("agent:main:telegram:group:g1")).is("group");
    (expect* deriveSessionChatType("agent:main:discord:channel:c1")).is("channel");
  });

  (deftest "detects legacy direct markers", () => {
    (expect* deriveSessionChatType("agent:main:telegram:dm:123456")).is("direct");
    (expect* deriveSessionChatType("telegram:dm:123456")).is("direct");
  });

  (deftest "detects legacy discord guild channel keys", () => {
    (expect* deriveSessionChatType("discord:acc-1:guild-123:channel-456")).is("channel");
  });

  (deftest "returns unknown for main or malformed session keys", () => {
    (expect* deriveSessionChatType("agent:main:main")).is("unknown");
    (expect* deriveSessionChatType("agent:main")).is("unknown");
    (expect* deriveSessionChatType("")).is("unknown");
  });
});

(deftest-group "session key canonicalization", () => {
  (deftest "parses agent keys case-insensitively and returns lowercase tokens", () => {
    (expect* parseAgentSessionKey("AGENT:Main:Hook:Webhook:42")).is-equal({
      agentId: "main",
      rest: "hook:webhook:42",
    });
  });

  (deftest "does not double-prefix already-qualified agent keys", () => {
    (expect* 
      toAgentStoreSessionKey({
        agentId: "main",
        requestKey: "agent:main:main",
      }),
    ).is("agent:main:main");
  });
});

(deftest-group "isValidAgentId", () => {
  (deftest "accepts valid agent ids", () => {
    (expect* isValidAgentId("main")).is(true);
    (expect* isValidAgentId("my-research_agent01")).is(true);
  });

  (deftest "rejects malformed agent ids", () => {
    (expect* isValidAgentId("")).is(false);
    (expect* isValidAgentId("Agent not found: xyz")).is(false);
    (expect* isValidAgentId("../../../etc/passwd")).is(false);
    (expect* isValidAgentId("a".repeat(65))).is(false);
  });
});
