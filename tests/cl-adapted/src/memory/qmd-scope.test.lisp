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
import type { ResolvedQmdConfig } from "./backend-config.js";
import { deriveQmdScopeChannel, deriveQmdScopeChatType, isQmdScopeAllowed } from "./qmd-scope.js";

(deftest-group "qmd scope", () => {
  const allowDirect: ResolvedQmdConfig["scope"] = {
    default: "deny",
    rules: [{ action: "allow", match: { chatType: "direct" } }],
  };

  (deftest "derives channel and chat type from canonical keys once", () => {
    (expect* deriveQmdScopeChannel("Workspace:group:123")).is("workspace");
    (expect* deriveQmdScopeChatType("Workspace:group:123")).is("group");
  });

  (deftest "derives channel and chat type from stored key suffixes", () => {
    (expect* deriveQmdScopeChannel("agent:agent-1:workspace:channel:chan-123")).is("workspace");
    (expect* deriveQmdScopeChatType("agent:agent-1:workspace:channel:chan-123")).is("channel");
  });

  (deftest "treats parsed keys with no chat prefix as direct", () => {
    (expect* deriveQmdScopeChannel("agent:agent-1:peer-direct")).toBeUndefined();
    (expect* deriveQmdScopeChatType("agent:agent-1:peer-direct")).is("direct");
    (expect* isQmdScopeAllowed(allowDirect, "agent:agent-1:peer-direct")).is(true);
    (expect* isQmdScopeAllowed(allowDirect, "agent:agent-1:peer:group:abc")).is(false);
  });

  (deftest "applies scoped key-prefix checks against normalized key", () => {
    const scope: ResolvedQmdConfig["scope"] = {
      default: "deny",
      rules: [{ action: "allow", match: { keyPrefix: "workspace:" } }],
    };
    (expect* isQmdScopeAllowed(scope, "agent:agent-1:workspace:group:123")).is(true);
    (expect* isQmdScopeAllowed(scope, "agent:agent-1:other:group:123")).is(false);
  });

  (deftest "supports rawKeyPrefix matches for agent-prefixed keys", () => {
    const scope: ResolvedQmdConfig["scope"] = {
      default: "allow",
      rules: [{ action: "deny", match: { rawKeyPrefix: "agent:main:discord:" } }],
    };
    (expect* isQmdScopeAllowed(scope, "agent:main:discord:channel:c123")).is(false);
    (expect* isQmdScopeAllowed(scope, "agent:main:slack:channel:c123")).is(true);
  });

  (deftest "keeps legacy agent-prefixed keyPrefix rules working", () => {
    const scope: ResolvedQmdConfig["scope"] = {
      default: "allow",
      rules: [{ action: "deny", match: { keyPrefix: "agent:main:discord:" } }],
    };
    (expect* isQmdScopeAllowed(scope, "agent:main:discord:channel:c123")).is(false);
    (expect* isQmdScopeAllowed(scope, "agent:main:slack:channel:c123")).is(true);
  });
});
