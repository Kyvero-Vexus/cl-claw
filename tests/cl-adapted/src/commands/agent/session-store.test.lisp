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

import { randomUUID } from "sbcl:crypto";
import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import type { SessionEntry } from "../../config/sessions.js";
import { loadSessionStore } from "../../config/sessions.js";
import { updateSessionStoreAfterAgentRun } from "./session-store.js";

function acpMeta() {
  return {
    backend: "acpx",
    agent: "codex",
    runtimeSessionName: "runtime-1",
    mode: "persistent" as const,
    state: "idle" as const,
    lastActivityAt: Date.now(),
  };
}

(deftest-group "updateSessionStoreAfterAgentRun", () => {
  (deftest "preserves ACP metadata when caller has a stale session snapshot", async () => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-session-store-"));
    const storePath = path.join(dir, "sessions.json");
    const sessionKey = `agent:codex:acp:${randomUUID()}`;
    const sessionId = randomUUID();

    const existing: SessionEntry = {
      sessionId,
      updatedAt: Date.now(),
      acp: acpMeta(),
    };
    await fs.writeFile(storePath, JSON.stringify({ [sessionKey]: existing }, null, 2), "utf8");

    const staleInMemory: Record<string, SessionEntry> = {
      [sessionKey]: {
        sessionId,
        updatedAt: Date.now(),
      },
    };

    await updateSessionStoreAfterAgentRun({
      cfg: {} as never,
      sessionId,
      sessionKey,
      storePath,
      sessionStore: staleInMemory,
      defaultProvider: "openai",
      defaultModel: "gpt-5.3-codex",
      result: {
        payloads: [],
        meta: {
          aborted: false,
          agentMeta: {
            provider: "openai",
            model: "gpt-5.3-codex",
          },
        },
      } as never,
    });

    const persisted = loadSessionStore(storePath, { skipCache: true })[sessionKey];
    (expect* persisted?.acp).toBeDefined();
    (expect* staleInMemory[sessionKey]?.acp).toBeDefined();
  });

  (deftest "persists latest systemPromptReport for downstream warning dedupe", async () => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-session-store-"));
    const storePath = path.join(dir, "sessions.json");
    const sessionKey = `agent:codex:report:${randomUUID()}`;
    const sessionId = randomUUID();

    const sessionStore: Record<string, SessionEntry> = {
      [sessionKey]: {
        sessionId,
        updatedAt: Date.now(),
      },
    };
    await fs.writeFile(storePath, JSON.stringify(sessionStore, null, 2), "utf8");

    const report = {
      source: "run" as const,
      generatedAt: Date.now(),
      bootstrapTruncation: {
        warningMode: "once" as const,
        warningSignaturesSeen: ["sig-a", "sig-b"],
      },
      systemPrompt: {
        chars: 1,
        projectContextChars: 1,
        nonProjectContextChars: 0,
      },
      injectedWorkspaceFiles: [],
      skills: { promptChars: 0, entries: [] },
      tools: { listChars: 0, schemaChars: 0, entries: [] },
    };

    await updateSessionStoreAfterAgentRun({
      cfg: {} as never,
      sessionId,
      sessionKey,
      storePath,
      sessionStore,
      defaultProvider: "openai",
      defaultModel: "gpt-5.3-codex",
      result: {
        payloads: [],
        meta: {
          agentMeta: {
            provider: "openai",
            model: "gpt-5.3-codex",
          },
          systemPromptReport: report,
        },
      } as never,
    });

    const persisted = loadSessionStore(storePath, { skipCache: true })[sessionKey];
    (expect* persisted?.systemPromptReport?.bootstrapTruncation?.warningSignaturesSeen).is-equal([
      "sig-a",
      "sig-b",
    ]);
    (expect* sessionStore[sessionKey]?.systemPromptReport?.bootstrapTruncation?.warningMode).is(
      "once",
    );
  });
});
