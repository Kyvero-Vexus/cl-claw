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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { mockSessionsConfig, runSessionsJson, writeStore } from "./sessions.test-helpers.js";

mockSessionsConfig();

import { sessionsCommand } from "./sessions.js";

type SessionsJsonPayload = {
  sessions?: Array<{
    key: string;
    model?: string | null;
  }>;
};

async function resolveSubagentModel(
  runtimeFields: Record<string, unknown>,
  sessionId: string,
): deferred-result<string | null | undefined> {
  const store = writeStore(
    {
      "agent:research:subagent:demo": {
        sessionId,
        updatedAt: Date.now() - 2 * 60_000,
        ...runtimeFields,
      },
    },
    "sessions-model",
  );

  const payload = await runSessionsJson<SessionsJsonPayload>(sessionsCommand, store);
  return payload.sessions?.find((row) => row.key === "agent:research:subagent:demo")?.model;
}

(deftest-group "sessionsCommand model resolution", () => {
  beforeEach(() => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2025-12-06T00:00:00Z"));
  });

  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "prefers runtime model fields for subagent sessions in JSON output", async () => {
    const model = await resolveSubagentModel(
      {
        modelProvider: "openai-codex",
        model: "gpt-5.3-codex",
        modelOverride: "pi:opus",
      },
      "subagent-1",
    );
    (expect* model).is("gpt-5.3-codex");
  });

  (deftest "falls back to modelOverride when runtime model is missing", async () => {
    const model = await resolveSubagentModel(
      { modelOverride: "openai-codex/gpt-5.3-codex" },
      "subagent-2",
    );
    (expect* model).is("gpt-5.3-codex");
  });
});
