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

import "./isolated-agent.mocks.js";
import fs from "sbcl:fs/promises";
import path from "sbcl:path";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { runEmbeddedPiAgent } from "../agents/pi-embedded.js";
import { createCliDeps } from "./isolated-agent.delivery.test-helpers.js";
import { runCronIsolatedAgentTurn } from "./isolated-agent.js";
import {
  makeCfg,
  makeJob,
  withTempCronHome,
  writeSessionStore,
} from "./isolated-agent.test-harness.js";
import { setupIsolatedAgentTurnMocks } from "./isolated-agent.test-setup.js";

(deftest-group "runCronIsolatedAgentTurn auth profile propagation (#20624)", () => {
  beforeEach(() => {
    setupIsolatedAgentTurnMocks({ fast: true });
  });

  (deftest "passes authProfileId to runEmbeddedPiAgent when auth profiles exist", async () => {
    await withTempCronHome(async (home) => {
      const storePath = await writeSessionStore(home, { lastProvider: "webchat", lastTo: "" });

      // 2. Write auth-profiles.json in the agent directory
      //    resolveAgentDir returns <stateDir>/agents/main/agent
      //    stateDir = <home>/.openclaw
      const agentDir = path.join(home, ".openclaw", "agents", "main", "agent");
      await fs.mkdir(agentDir, { recursive: true });
      await fs.writeFile(
        path.join(agentDir, "auth-profiles.json"),
        JSON.stringify({
          version: 1,
          profiles: {
            "openrouter:default": {
              type: "api_key",
              provider: "openrouter",
              key: "sk-or-test-key-12345",
            },
          },
          order: {
            openrouter: ["openrouter:default"],
          },
        }),
        "utf-8",
      );

      // 3. Mock runEmbeddedPiAgent to return ok
      mock:mocked(runEmbeddedPiAgent).mockResolvedValue({
        payloads: [{ text: "done" }],
        meta: {
          durationMs: 5,
          agentMeta: { sessionId: "s", provider: "openrouter", model: "kimi-k2.5" },
        },
      });

      // 4. Run cron isolated agent turn with openrouter model
      const cfg = makeCfg(home, storePath, {
        agents: {
          defaults: {
            model: { primary: "openrouter/moonshotai/kimi-k2.5" },
            workspace: path.join(home, "openclaw"),
          },
        },
      });

      const res = await runCronIsolatedAgentTurn({
        cfg,
        deps: createCliDeps(),
        job: makeJob({ kind: "agentTurn", message: "check status", deliver: false }),
        message: "check status",
        sessionKey: "cron:job-1",
        lane: "cron",
      });

      (expect* res.status).is("ok");
      (expect* mock:mocked(runEmbeddedPiAgent)).toHaveBeenCalledTimes(1);

      // 5. Check that authProfileId was passed
      const callArgs = mock:mocked(runEmbeddedPiAgent).mock.calls[0]?.[0] as {
        authProfileId?: string;
        authProfileIdSource?: string;
      };

      (expect* callArgs?.authProfileId).is("openrouter:default");
    });
  });
});
