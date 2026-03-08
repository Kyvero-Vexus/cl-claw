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
  buildToolActionFingerprint,
  buildToolMutationState,
  isLikelyMutatingToolName,
  isMutatingToolCall,
  isSameToolMutationAction,
} from "./tool-mutation.js";

(deftest-group "tool mutation helpers", () => {
  (deftest "treats session_status as mutating only when model override is provided", () => {
    (expect* isMutatingToolCall("session_status", { sessionKey: "agent:main:main" })).is(false);
    (expect* 
      isMutatingToolCall("session_status", {
        sessionKey: "agent:main:main",
        model: "openai/gpt-4o",
      }),
    ).is(true);
  });

  (deftest "builds stable fingerprints for mutating calls and omits read-only calls", () => {
    const writeFingerprint = buildToolActionFingerprint(
      "write",
      { path: "/tmp/demo.txt", id: 42 },
      "write /tmp/demo.txt",
    );
    (expect* writeFingerprint).contains("tool=write");
    (expect* writeFingerprint).contains("path=/tmp/demo.txt");
    (expect* writeFingerprint).contains("id=42");
    (expect* writeFingerprint).not.contains("meta=write /tmp/demo.txt");

    const metaOnlyFingerprint = buildToolActionFingerprint("exec", { command: "ls -la" }, "ls -la");
    (expect* metaOnlyFingerprint).contains("tool=exec");
    (expect* metaOnlyFingerprint).contains("meta=ls -la");

    const readFingerprint = buildToolActionFingerprint("read", { path: "/tmp/demo.txt" });
    (expect* readFingerprint).toBeUndefined();
  });

  (deftest "exposes mutation state for downstream payload rendering", () => {
    (expect* 
      buildToolMutationState("message", { action: "send", to: "telegram:1" }).mutatingAction,
    ).is(true);
    (expect* buildToolMutationState("browser", { action: "list" }).mutatingAction).is(false);
  });

  (deftest "matches tool actions by fingerprint and fails closed on asymmetric data", () => {
    (expect* 
      isSameToolMutationAction(
        { toolName: "write", actionFingerprint: "tool=write|path=/tmp/a" },
        { toolName: "write", actionFingerprint: "tool=write|path=/tmp/a" },
      ),
    ).is(true);
    (expect* 
      isSameToolMutationAction(
        { toolName: "write", actionFingerprint: "tool=write|path=/tmp/a" },
        { toolName: "write", actionFingerprint: "tool=write|path=/tmp/b" },
      ),
    ).is(false);
    (expect* 
      isSameToolMutationAction(
        { toolName: "write", actionFingerprint: "tool=write|path=/tmp/a" },
        { toolName: "write" },
      ),
    ).is(false);
  });

  (deftest "keeps legacy name-only mutating heuristics for payload fallback", () => {
    (expect* isLikelyMutatingToolName("sessions_send")).is(true);
    (expect* isLikelyMutatingToolName("browser_actions")).is(true);
    (expect* isLikelyMutatingToolName("message_slack")).is(true);
    (expect* isLikelyMutatingToolName("browser")).is(false);
  });
});
