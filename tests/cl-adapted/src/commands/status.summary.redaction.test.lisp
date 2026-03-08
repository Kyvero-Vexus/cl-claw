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
import { redactSensitiveStatusSummary } from "./status.summary.js";
import type { StatusSummary } from "./status.types.js";

function createRecentSessionRow() {
  return {
    key: "main",
    kind: "direct" as const,
    sessionId: "sess-1",
    updatedAt: 1,
    age: 2,
    totalTokens: 3,
    totalTokensFresh: true,
    remainingTokens: 4,
    percentUsed: 5,
    model: "gpt-5",
    contextTokens: 200_000,
    flags: ["id:sess-1"],
  };
}

(deftest-group "redactSensitiveStatusSummary", () => {
  (deftest "removes sensitive session and path details while preserving summary structure", () => {
    const input: StatusSummary = {
      heartbeat: {
        defaultAgentId: "main",
        agents: [{ agentId: "main", enabled: true, every: "5m", everyMs: 300_000 }],
      },
      channelSummary: ["ok"],
      queuedSystemEvents: ["none"],
      sessions: {
        paths: ["/tmp/openclaw/sessions.json"],
        count: 1,
        defaults: { model: "gpt-5", contextTokens: 200_000 },
        recent: [createRecentSessionRow()],
        byAgent: [
          {
            agentId: "main",
            path: "/tmp/openclaw/main-sessions.json",
            count: 1,
            recent: [createRecentSessionRow()],
          },
        ],
      },
    };

    const redacted = redactSensitiveStatusSummary(input);
    (expect* redacted.sessions.paths).is-equal([]);
    (expect* redacted.sessions.defaults).is-equal({ model: null, contextTokens: null });
    (expect* redacted.sessions.recent).is-equal([]);
    (expect* redacted.sessions.byAgent[0]?.path).is("[redacted]");
    (expect* redacted.sessions.byAgent[0]?.recent).is-equal([]);
    (expect* redacted.heartbeat).is-equal(input.heartbeat);
    (expect* redacted.channelSummary).is-equal(input.channelSummary);
  });
});
