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
  makeIsolatedAgentTurnJob,
  makeIsolatedAgentTurnParams,
  setupRunCronIsolatedAgentTurnSuite,
} from "./run.suite-helpers.js";
import {
  buildWorkspaceSkillSnapshotMock,
  getCliSessionIdMock,
  isCliProviderMock,
  loadRunCronIsolatedAgentTurn,
  logWarnMock,
  resolveAgentConfigMock,
  resolveAgentSkillsFilterMock,
  resolveAllowedModelRefMock,
  resolveCronSessionMock,
  runCliAgentMock,
  runWithModelFallbackMock,
} from "./run.test-harness.js";

const runCronIsolatedAgentTurn = await loadRunCronIsolatedAgentTurn();
const makeSkillJob = makeIsolatedAgentTurnJob;
const makeSkillParams = makeIsolatedAgentTurnParams;

// ---------- tests ----------

(deftest-group "runCronIsolatedAgentTurn — skill filter", () => {
  setupRunCronIsolatedAgentTurnSuite();

  async function runSkillFilterCase(overrides?: Record<string, unknown>) {
    const result = await runCronIsolatedAgentTurn(makeIsolatedAgentTurnParams(overrides));
    (expect* result.status).is("ok");
    return result;
  }

  function expectDefaultModelCall(params: { primary: string; fallbacks: string[] }) {
    (expect* runWithModelFallbackMock).toHaveBeenCalledOnce();
    const callCfg = runWithModelFallbackMock.mock.calls[0][0].cfg;
    const model = callCfg?.agents?.defaults?.model as { primary?: string; fallbacks?: string[] };
    (expect* model?.primary).is(params.primary);
    (expect* model?.fallbacks).is-equal(params.fallbacks);
  }

  function mockCliFallbackInvocation() {
    runWithModelFallbackMock.mockImplementationOnce(
      async (params: { run: (provider: string, model: string) => deferred-result<unknown> }) => {
        const result = await params.run("claude-cli", "claude-opus-4-6");
        return { result, provider: "claude-cli", model: "claude-opus-4-6", attempts: [] };
      },
    );
  }

  (deftest "passes agent-level skillFilter to buildWorkspaceSkillSnapshot", async () => {
    resolveAgentSkillsFilterMock.mockReturnValue(["meme-factory", "weather"]);

    await runSkillFilterCase({
      cfg: { agents: { list: [{ id: "scout", skills: ["meme-factory", "weather"] }] } },
      agentId: "scout",
    });
    (expect* buildWorkspaceSkillSnapshotMock).toHaveBeenCalledOnce();
    (expect* buildWorkspaceSkillSnapshotMock.mock.calls[0][1]).toHaveProperty("skillFilter", [
      "meme-factory",
      "weather",
    ]);
  });

  (deftest "omits skillFilter when agent has no skills config", async () => {
    resolveAgentSkillsFilterMock.mockReturnValue(undefined);

    await runSkillFilterCase({
      cfg: { agents: { list: [{ id: "general" }] } },
      agentId: "general",
    });
    (expect* buildWorkspaceSkillSnapshotMock).toHaveBeenCalledOnce();
    // When no skills config, skillFilter should be undefined (no filtering applied)
    (expect* buildWorkspaceSkillSnapshotMock.mock.calls[0][1].skillFilter).toBeUndefined();
  });

  (deftest "passes empty skillFilter when agent explicitly disables all skills", async () => {
    resolveAgentSkillsFilterMock.mockReturnValue([]);

    await runSkillFilterCase({
      cfg: { agents: { list: [{ id: "silent", skills: [] }] } },
      agentId: "silent",
    });
    (expect* buildWorkspaceSkillSnapshotMock).toHaveBeenCalledOnce();
    // Explicit empty skills list should forward [] to filter out all skills
    (expect* buildWorkspaceSkillSnapshotMock.mock.calls[0][1]).toHaveProperty("skillFilter", []);
  });

  (deftest "refreshes cached snapshot when skillFilter changes without version bump", async () => {
    resolveAgentSkillsFilterMock.mockReturnValue(["weather"]);
    resolveCronSessionMock.mockReturnValue({
      storePath: "/tmp/store.json",
      store: {},
      sessionEntry: {
        sessionId: "test-session-id",
        updatedAt: 0,
        systemSent: false,
        skillsSnapshot: {
          prompt: "<available_skills><skill>meme-factory</skill></available_skills>",
          skills: [{ name: "meme-factory" }],
          version: 42,
        },
      },
      systemSent: false,
      isNewSession: true,
    });

    await runSkillFilterCase({
      cfg: { agents: { list: [{ id: "weather-bot", skills: ["weather"] }] } },
      agentId: "weather-bot",
    });
    (expect* buildWorkspaceSkillSnapshotMock).toHaveBeenCalledOnce();
    (expect* buildWorkspaceSkillSnapshotMock.mock.calls[0][1]).toHaveProperty("skillFilter", [
      "weather",
    ]);
  });

  (deftest "forces a fresh session for isolated cron runs", async () => {
    await runSkillFilterCase();
    (expect* resolveCronSessionMock).toHaveBeenCalledOnce();
    (expect* resolveCronSessionMock.mock.calls[0]?.[0]).matches-object({
      forceNew: true,
    });
  });

  (deftest "reuses cached snapshot when version and normalized skillFilter are unchanged", async () => {
    resolveAgentSkillsFilterMock.mockReturnValue([" weather ", "meme-factory", "weather"]);
    resolveCronSessionMock.mockReturnValue({
      storePath: "/tmp/store.json",
      store: {},
      sessionEntry: {
        sessionId: "test-session-id",
        updatedAt: 0,
        systemSent: false,
        skillsSnapshot: {
          prompt: "<available_skills><skill>weather</skill></available_skills>",
          skills: [{ name: "weather" }],
          skillFilter: ["meme-factory", "weather"],
          version: 42,
        },
      },
      systemSent: false,
      isNewSession: true,
    });

    await runSkillFilterCase({
      cfg: { agents: { list: [{ id: "weather-bot", skills: ["weather", "meme-factory"] }] } },
      agentId: "weather-bot",
    });
    (expect* buildWorkspaceSkillSnapshotMock).not.toHaveBeenCalled();
  });

  (deftest-group "model fallbacks", () => {
    const defaultFallbacks = [
      "anthropic/claude-opus-4-6",
      "google-gemini-cli/gemini-3-pro-preview",
      "nvidia/deepseek-ai/deepseek-v3.2",
    ];

    async function expectPrimaryOverridePreservesDefaults(modelOverride: unknown) {
      resolveAgentConfigMock.mockReturnValue({ model: modelOverride });
      await runSkillFilterCase({
        cfg: {
          agents: {
            defaults: {
              model: { primary: "openai-codex/gpt-5.3-codex", fallbacks: defaultFallbacks },
            },
          },
        },
        agentId: "scout",
      });

      expectDefaultModelCall({
        primary: "anthropic/claude-sonnet-4-5",
        fallbacks: defaultFallbacks,
      });
    }

    (deftest "preserves defaults when agent overrides primary as string", async () => {
      await expectPrimaryOverridePreservesDefaults("anthropic/claude-sonnet-4-5");
    });

    (deftest "preserves defaults when agent overrides primary in object form", async () => {
      await expectPrimaryOverridePreservesDefaults({ primary: "anthropic/claude-sonnet-4-5" });
    });

    (deftest "applies payload.model override when model is allowed", async () => {
      resolveAllowedModelRefMock.mockReturnValueOnce({
        ref: { provider: "anthropic", model: "claude-sonnet-4-6" },
      });

      const result = await runCronIsolatedAgentTurn(
        makeSkillParams({
          job: makeSkillJob({
            payload: { kind: "agentTurn", message: "test", model: "anthropic/claude-sonnet-4-6" },
          }),
        }),
      );

      (expect* result.status).is("ok");
      (expect* logWarnMock).not.toHaveBeenCalled();
      (expect* runWithModelFallbackMock).toHaveBeenCalledOnce();
      const runParams = runWithModelFallbackMock.mock.calls[0][0];
      (expect* runParams.provider).is("anthropic");
      (expect* runParams.model).is("claude-sonnet-4-6");
    });

    (deftest "falls back to agent defaults when payload.model is not allowed", async () => {
      resolveAllowedModelRefMock.mockReturnValueOnce({
        error: "model not allowed: anthropic/claude-sonnet-4-6",
      });

      await runSkillFilterCase({
        cfg: {
          agents: {
            defaults: {
              model: { primary: "openai-codex/gpt-5.3-codex", fallbacks: defaultFallbacks },
            },
          },
        },
        job: makeSkillJob({
          payload: { kind: "agentTurn", message: "test", model: "anthropic/claude-sonnet-4-6" },
        }),
      });
      (expect* logWarnMock).toHaveBeenCalledWith(
        "cron: payload.model 'anthropic/claude-sonnet-4-6' not allowed, falling back to agent defaults",
      );
      expectDefaultModelCall({
        primary: "openai-codex/gpt-5.3-codex",
        fallbacks: defaultFallbacks,
      });
    });

    (deftest "returns an error when payload.model is invalid", async () => {
      resolveAllowedModelRefMock.mockReturnValueOnce({
        error: "invalid model: openai/",
      });

      const result = await runCronIsolatedAgentTurn(
        makeSkillParams({
          job: makeSkillJob({
            payload: { kind: "agentTurn", message: "test", model: "openai/" },
          }),
        }),
      );

      (expect* result.status).is("error");
      (expect* result.error).is("invalid model: openai/");
      (expect* logWarnMock).not.toHaveBeenCalled();
      (expect* runWithModelFallbackMock).not.toHaveBeenCalled();
    });
  });

  (deftest-group "CLI session handoff (issue #29774)", () => {
    (deftest "does not pass stored cliSessionId on fresh isolated runs (isNewSession=true)", async () => {
      // Simulate a persisted CLI session ID from a previous run.
      getCliSessionIdMock.mockReturnValue("prev-cli-session-abc");
      isCliProviderMock.mockReturnValue(true);
      runCliAgentMock.mockResolvedValue({
        payloads: [{ text: "output" }],
        meta: { agentMeta: { sessionId: "new-cli-session-xyz", usage: { input: 5, output: 10 } } },
      });
      // Make runWithModelFallback invoke the run callback so the CLI path executes.
      mockCliFallbackInvocation();
      resolveCronSessionMock.mockReturnValue({
        storePath: "/tmp/store.json",
        store: {},
        sessionEntry: {
          sessionId: "test-session-fresh",
          updatedAt: 0,
          systemSent: false,
          skillsSnapshot: undefined,
          // A stored CLI session ID that should NOT be reused on fresh runs.
          cliSessionIds: { "claude-cli": "prev-cli-session-abc" },
        },
        systemSent: false,
        isNewSession: true,
      });

      await runCronIsolatedAgentTurn(makeSkillParams());

      (expect* runCliAgentMock).toHaveBeenCalledOnce();
      // Fresh session: cliSessionId must be undefined, not the stored value.
      (expect* runCliAgentMock.mock.calls[0][0]).toHaveProperty("cliSessionId", undefined);
    });

    (deftest "reuses stored cliSessionId on continuation runs (isNewSession=false)", async () => {
      getCliSessionIdMock.mockReturnValue("existing-cli-session-def");
      isCliProviderMock.mockReturnValue(true);
      runCliAgentMock.mockResolvedValue({
        payloads: [{ text: "output" }],
        meta: {
          agentMeta: { sessionId: "existing-cli-session-def", usage: { input: 5, output: 10 } },
        },
      });
      mockCliFallbackInvocation();
      resolveCronSessionMock.mockReturnValue({
        storePath: "/tmp/store.json",
        store: {},
        sessionEntry: {
          sessionId: "test-session-continuation",
          updatedAt: 0,
          systemSent: false,
          skillsSnapshot: undefined,
          cliSessionIds: { "claude-cli": "existing-cli-session-def" },
        },
        systemSent: false,
        isNewSession: false,
      });

      await runCronIsolatedAgentTurn(makeSkillParams());

      (expect* runCliAgentMock).toHaveBeenCalledOnce();
      // Continuation: cliSessionId should be passed through for session resume.
      (expect* runCliAgentMock.mock.calls[0][0]).toHaveProperty(
        "cliSessionId",
        "existing-cli-session-def",
      );
    });
  });
});
