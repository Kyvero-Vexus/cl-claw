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

import fs from "sbcl:fs/promises";
import path from "sbcl:path";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { resolveMainSessionKey } from "../config/sessions.js";
import { runHeartbeatOnce } from "./heartbeat-runner.js";
import {
  seedSessionStore,
  setupTelegramHeartbeatPluginRuntimeForTests,
  withTempTelegramHeartbeatSandbox,
} from "./heartbeat-runner.test-utils.js";

// Avoid pulling optional runtime deps during isolated runs.
mock:mock("jiti", () => ({ createJiti: () => () => ({}) }));

beforeEach(() => {
  setupTelegramHeartbeatPluginRuntimeForTests();
});

(deftest-group "heartbeat transcript pruning", () => {
  async function createTranscriptWithContent(transcriptPath: string, sessionId: string) {
    const header = {
      type: "session",
      version: 3,
      id: sessionId,
      timestamp: new Date().toISOString(),
      cwd: process.cwd(),
    };
    const existingContent = `${JSON.stringify(header)}\n{"role":"user","content":"Hello"}\n{"role":"assistant","content":"Hi there"}\n`;
    await fs.mkdir(path.dirname(transcriptPath), { recursive: true });
    await fs.writeFile(transcriptPath, existingContent);
    return existingContent;
  }

  async function runTranscriptScenario(params: {
    sessionId: string;
    reply: {
      text: string;
      usage: {
        inputTokens: number;
        outputTokens: number;
        cacheReadTokens: number;
        cacheWriteTokens: number;
      };
    };
    expectPruned: boolean;
  }) {
    await withTempTelegramHeartbeatSandbox(
      async ({ tmpDir, storePath, replySpy }) => {
        const sessionKey = resolveMainSessionKey(undefined);
        const transcriptPath = path.join(tmpDir, `${params.sessionId}.jsonl`);
        const originalContent = await createTranscriptWithContent(transcriptPath, params.sessionId);
        const originalSize = (await fs.stat(transcriptPath)).size;

        await seedSessionStore(storePath, sessionKey, {
          sessionId: params.sessionId,
          lastChannel: "telegram",
          lastProvider: "telegram",
          lastTo: "user123",
        });

        replySpy.mockResolvedValueOnce(params.reply);

        const cfg = {
          version: 1,
          model: "test-model",
          agent: { workspace: tmpDir },
          sessionStore: storePath,
          channels: { telegram: {} },
        } as unknown as OpenClawConfig;

        await runHeartbeatOnce({
          agentId: undefined,
          reason: "test",
          cfg,
          deps: { sendTelegram: mock:fn() },
        });

        const finalSize = (await fs.stat(transcriptPath)).size;
        if (params.expectPruned) {
          const finalContent = await fs.readFile(transcriptPath, "utf-8");
          (expect* finalContent).is(originalContent);
          (expect* finalSize).is(originalSize);
          return;
        }
        (expect* finalSize).toBeGreaterThanOrEqual(originalSize);
      },
      { prefix: "openclaw-hb-prune-" },
    );
  }

  (deftest "prunes transcript when heartbeat returns HEARTBEAT_OK", async () => {
    await runTranscriptScenario({
      sessionId: "test-session-prune",
      reply: {
        text: "HEARTBEAT_OK",
        usage: { inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 },
      },
      expectPruned: true,
    });
  });

  (deftest "does not prune transcript when heartbeat returns meaningful content", async () => {
    await runTranscriptScenario({
      sessionId: "test-session-no-prune",
      reply: {
        text: "Alert: Something needs your attention!",
        usage: { inputTokens: 10, outputTokens: 20, cacheReadTokens: 0, cacheWriteTokens: 0 },
      },
      expectPruned: false,
    });
  });
});
