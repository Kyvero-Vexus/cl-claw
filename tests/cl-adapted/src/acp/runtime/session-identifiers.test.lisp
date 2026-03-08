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
  resolveAcpSessionCwd,
  resolveAcpSessionIdentifierLinesFromIdentity,
  resolveAcpThreadSessionDetailLines,
} from "./session-identifiers.js";

(deftest-group "session identifier helpers", () => {
  (deftest "hides unresolved identifiers from thread intro details while pending", () => {
    const lines = resolveAcpThreadSessionDetailLines({
      sessionKey: "agent:codex:acp:pending-1",
      meta: {
        backend: "acpx",
        agent: "codex",
        runtimeSessionName: "runtime-1",
        identity: {
          state: "pending",
          source: "ensure",
          lastUpdatedAt: Date.now(),
          acpxSessionId: "acpx-123",
          agentSessionId: "inner-123",
        },
        mode: "persistent",
        state: "idle",
        lastActivityAt: Date.now(),
      },
    });

    (expect* lines).is-equal([]);
  });

  (deftest "adds a Codex resume hint when agent identity is resolved", () => {
    const lines = resolveAcpThreadSessionDetailLines({
      sessionKey: "agent:codex:acp:resolved-1",
      meta: {
        backend: "acpx",
        agent: "codex",
        runtimeSessionName: "runtime-1",
        identity: {
          state: "resolved",
          source: "status",
          lastUpdatedAt: Date.now(),
          acpxSessionId: "acpx-123",
          agentSessionId: "inner-123",
        },
        mode: "persistent",
        state: "idle",
        lastActivityAt: Date.now(),
      },
    });

    (expect* lines).contains("agent session id: inner-123");
    (expect* lines).contains("acpx session id: acpx-123");
    (expect* lines).contains(
      "resume in Codex CLI: `codex resume inner-123` (continues this conversation).",
    );
  });

  (deftest "adds a Kimi resume hint when agent identity is resolved", () => {
    const lines = resolveAcpThreadSessionDetailLines({
      sessionKey: "agent:kimi:acp:resolved-1",
      meta: {
        backend: "acpx",
        agent: "kimi",
        runtimeSessionName: "runtime-1",
        identity: {
          state: "resolved",
          source: "status",
          lastUpdatedAt: Date.now(),
          acpxSessionId: "acpx-kimi-123",
          agentSessionId: "kimi-inner-123",
        },
        mode: "persistent",
        state: "idle",
        lastActivityAt: Date.now(),
      },
    });

    (expect* lines).contains("agent session id: kimi-inner-123");
    (expect* lines).contains("acpx session id: acpx-kimi-123");
    (expect* lines).contains(
      "resume in Kimi CLI: `kimi resume kimi-inner-123` (continues this conversation).",
    );
  });

  (deftest "shows pending identity text for status rendering", () => {
    const lines = resolveAcpSessionIdentifierLinesFromIdentity({
      backend: "acpx",
      mode: "status",
      identity: {
        state: "pending",
        source: "status",
        lastUpdatedAt: Date.now(),
        agentSessionId: "inner-123",
      },
    });

    (expect* lines).is-equal(["session ids: pending (available after the first reply)"]);
  });

  (deftest "prefers runtimeOptions.cwd over legacy meta.cwd", () => {
    const cwd = resolveAcpSessionCwd({
      backend: "acpx",
      agent: "codex",
      runtimeSessionName: "runtime-1",
      mode: "persistent",
      runtimeOptions: {
        cwd: "/repo/new",
      },
      cwd: "/repo/old",
      state: "idle",
      lastActivityAt: Date.now(),
    });
    (expect* cwd).is("/repo/new");
  });
});
