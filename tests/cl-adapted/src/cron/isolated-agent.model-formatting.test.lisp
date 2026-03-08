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
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { loadModelCatalog } from "../agents/model-catalog.js";
import { runEmbeddedPiAgent } from "../agents/pi-embedded.js";
import { runCronIsolatedAgentTurn } from "./isolated-agent.js";
import {
  makeCfg,
  makeJob,
  withTempCronHome,
  writeSessionStoreEntries,
} from "./isolated-agent.test-harness.js";
import type { CronJob } from "./types.js";

const withTempHome = withTempCronHome;

function makeDeps() {
  return {
    sendMessageSlack: mock:fn(),
    sendMessageWhatsApp: mock:fn(),
    sendMessageTelegram: mock:fn(),
    sendMessageDiscord: mock:fn(),
    sendMessageSignal: mock:fn(),
    sendMessageIMessage: mock:fn(),
  };
}

function mockEmbeddedOk() {
  mock:mocked(runEmbeddedPiAgent).mockResolvedValue({
    payloads: [{ text: "ok" }],
    meta: {
      durationMs: 5,
      agentMeta: { sessionId: "s", provider: "p", model: "m" },
    },
  });
}

/**
 * Extract the provider and model from the last runEmbeddedPiAgent call.
 */
function lastEmbeddedCall(): { provider?: string; model?: string } {
  const calls = mock:mocked(runEmbeddedPiAgent).mock.calls;
  (expect* calls.length).toBeGreaterThan(0);
  return calls.at(-1)?.[0] as { provider?: string; model?: string };
}

const DEFAULT_MESSAGE = "do it";

type TurnOptions = {
  cfgOverrides?: Parameters<typeof makeCfg>[2];
  jobPayload?: CronJob["payload"];
  sessionKey?: string;
  storeEntries?: Record<string, Record<string, unknown>>;
};

async function runTurnCore(home: string, options: TurnOptions = {}) {
  const storePath = await writeSessionStoreEntries(home, {
    "agent:main:main": {
      sessionId: "main-session",
      updatedAt: Date.now(),
      lastProvider: "webchat",
      lastTo: "",
    },
    ...options.storeEntries,
  });
  mockEmbeddedOk();

  const jobPayload = options.jobPayload ?? {
    kind: "agentTurn" as const,
    message: DEFAULT_MESSAGE,
    deliver: false,
  };

  const res = await runCronIsolatedAgentTurn({
    cfg: makeCfg(home, storePath, options.cfgOverrides),
    deps: makeDeps(),
    job: makeJob(jobPayload),
    message: DEFAULT_MESSAGE,
    sessionKey: options.sessionKey ?? "cron:job-1",
    lane: "cron",
  });

  return res;
}

/** Like runTurn but does NOT assert the embedded agent was called (for error paths). */
async function runErrorTurn(home: string, options: TurnOptions = {}) {
  const res = await runTurnCore(home, options);
  return { res };
}

async function runTurn(home: string, options: TurnOptions = {}) {
  const res = await runTurnCore(home, options);
  return { res, call: lastEmbeddedCall() };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

(deftest-group "cron model formatting and precedence edge cases", () => {
  beforeEach(() => {
    mock:mocked(runEmbeddedPiAgent).mockClear();
    mock:mocked(loadModelCatalog).mockResolvedValue([]);
  });

  // ------ provider/model string splitting ------

  (deftest-group "parseModelRef formatting", () => {
    (deftest "splits standard provider/model", async () => {
      await withTempHome(async (home) => {
        const { res, call } = await runTurn(home, {
          jobPayload: { kind: "agentTurn", message: DEFAULT_MESSAGE, model: "openai/gpt-4.1-mini" },
        });
        (expect* res.status).is("ok");
        (expect* call.provider).is("openai");
        (expect* call.model).is("gpt-4.1-mini");
      });
    });

    (deftest "handles leading/trailing whitespace in model string", async () => {
      await withTempHome(async (home) => {
        const { res, call } = await runTurn(home, {
          jobPayload: {
            kind: "agentTurn",
            message: DEFAULT_MESSAGE,
            model: "  openai/gpt-4.1-mini  ",
          },
        });
        (expect* res.status).is("ok");
        (expect* call.provider).is("openai");
        (expect* call.model).is("gpt-4.1-mini");
      });
    });

    (deftest "handles openrouter nested provider paths", async () => {
      await withTempHome(async (home) => {
        const { res, call } = await runTurn(home, {
          jobPayload: {
            kind: "agentTurn",
            message: DEFAULT_MESSAGE,
            model: "openrouter/meta-llama/llama-3.3-70b:free",
          },
        });
        (expect* res.status).is("ok");
        (expect* call.provider).is("openrouter");
        (expect* call.model).is("meta-llama/llama-3.3-70b:free");
      });
    });

    (deftest "rejects model with trailing slash (empty model name)", async () => {
      await withTempHome(async (home) => {
        const { res } = await runErrorTurn(home, {
          jobPayload: { kind: "agentTurn", message: DEFAULT_MESSAGE, model: "openai/" },
        });
        (expect* res.status).is("error");
        (expect* res.error).toMatch(/invalid model/i);
        (expect* mock:mocked(runEmbeddedPiAgent)).not.toHaveBeenCalled();
      });
    });

    (deftest "rejects model with leading slash (empty provider)", async () => {
      await withTempHome(async (home) => {
        const { res } = await runErrorTurn(home, {
          jobPayload: { kind: "agentTurn", message: DEFAULT_MESSAGE, model: "/gpt-4.1-mini" },
        });
        (expect* res.status).is("error");
        (expect* res.error).toMatch(/invalid model/i);
        (expect* mock:mocked(runEmbeddedPiAgent)).not.toHaveBeenCalled();
      });
    });

    (deftest "normalizes provider casing", async () => {
      await withTempHome(async (home) => {
        const { res, call } = await runTurn(home, {
          jobPayload: {
            kind: "agentTurn",
            message: DEFAULT_MESSAGE,
            model: "OpenAI/gpt-4.1-mini",
          },
        });
        (expect* res.status).is("ok");
        (expect* call.provider).is("openai");
        (expect* call.model).is("gpt-4.1-mini");
      });
    });

    (deftest "normalizes anthropic model aliases", async () => {
      await withTempHome(async (home) => {
        const { res, call } = await runTurn(home, {
          jobPayload: {
            kind: "agentTurn",
            message: DEFAULT_MESSAGE,
            model: "anthropic/opus-4.5",
          },
        });
        (expect* res.status).is("ok");
        (expect* call.provider).is("anthropic");
        (expect* call.model).is("claude-opus-4-5");
      });
    });

    (deftest "normalizes bedrock provider alias", async () => {
      await withTempHome(async (home) => {
        const { res, call } = await runTurn(home, {
          jobPayload: {
            kind: "agentTurn",
            message: DEFAULT_MESSAGE,
            model: "bedrock/claude-sonnet-4-5",
          },
        });
        (expect* res.status).is("ok");
        (expect* call.provider).is("amazon-bedrock");
      });
    });
  });

  // ------ precedence: job payload > session override > default ------

  (deftest-group "model precedence isolation", () => {
    (deftest "job payload model overrides default (anthropic → openai)", async () => {
      // Default in makeCfg is anthropic/claude-opus-4-5.
      // Job payload sets openai/gpt-4.1-mini. Provider must be openai.
      await withTempHome(async (home) => {
        const { call } = await runTurn(home, {
          jobPayload: {
            kind: "agentTurn",
            message: DEFAULT_MESSAGE,
            model: "openai/gpt-4.1-mini",
          },
        });
        (expect* call.provider).is("openai");
        (expect* call.model).is("gpt-4.1-mini");
      });
    });

    (deftest "session override applies when no job payload model is present", async () => {
      // No model in job payload. Session store has openai override.
      // Provider must be openai, not the default anthropic.
      await withTempHome(async (home) => {
        const { call } = await runTurn(home, {
          jobPayload: { kind: "agentTurn", message: DEFAULT_MESSAGE, deliver: false },
          storeEntries: {
            "agent:main:cron:job-1": {
              sessionId: "existing-session",
              updatedAt: Date.now(),
              providerOverride: "openai",
              modelOverride: "gpt-4.1-mini",
            },
          },
        });
        (expect* call.provider).is("openai");
        (expect* call.model).is("gpt-4.1-mini");
      });
    });

    (deftest "job payload model wins over conflicting session override", async () => {
      // Job payload says anthropic. Session says openai. Job must win.
      await withTempHome(async (home) => {
        const { call } = await runTurn(home, {
          jobPayload: {
            kind: "agentTurn",
            message: DEFAULT_MESSAGE,
            model: "anthropic/claude-sonnet-4-5",
            deliver: false,
          },
          storeEntries: {
            "agent:main:cron:job-1": {
              sessionId: "existing-session",
              updatedAt: Date.now(),
              providerOverride: "openai",
              modelOverride: "gpt-4.1-mini",
            },
          },
        });
        (expect* call.provider).is("anthropic");
        (expect* call.model).is("claude-sonnet-4-5");
      });
    });

    (deftest "falls through to default when no override is present", async () => {
      await withTempHome(async (home) => {
        const { call } = await runTurn(home, {
          jobPayload: { kind: "agentTurn", message: DEFAULT_MESSAGE, deliver: false },
        });
        // makeCfg default is anthropic/claude-opus-4-5
        (expect* call.provider).is("anthropic");
        (expect* call.model).is("claude-opus-4-5");
      });
    });
  });

  // ------ sequential runs with different overrides (the CI failure pattern) ------

  (deftest-group "sequential model switches (CI failure regression)", () => {
    (deftest "openai override → session openai → job anthropic: each step resolves correctly", async () => {
      // This reproduces the exact pattern from the CI failure.
      // Three sequential calls in one temp home, switching providers.
      await withTempHome(async (home) => {
        // Step 1: Job payload says openai
        mock:mocked(runEmbeddedPiAgent).mockClear();
        const step1 = await runTurn(home, {
          jobPayload: {
            kind: "agentTurn",
            message: DEFAULT_MESSAGE,
            model: "openai/gpt-4.1-mini",
          },
        });
        (expect* step1.call.provider).is("openai");
        (expect* step1.call.model).is("gpt-4.1-mini");

        // Step 2: No job model, session store says openai
        mock:mocked(runEmbeddedPiAgent).mockClear();
        mockEmbeddedOk();
        const step2 = await runTurn(home, {
          jobPayload: { kind: "agentTurn", message: DEFAULT_MESSAGE, deliver: false },
          storeEntries: {
            "agent:main:cron:job-1": {
              sessionId: "existing-session",
              updatedAt: Date.now(),
              providerOverride: "openai",
              modelOverride: "gpt-4.1-mini",
            },
          },
        });
        (expect* step2.call.provider).is("openai");
        (expect* step2.call.model).is("gpt-4.1-mini");

        // Step 3: Job payload says anthropic, session store still says openai
        mock:mocked(runEmbeddedPiAgent).mockClear();
        mockEmbeddedOk();
        const step3 = await runTurn(home, {
          jobPayload: {
            kind: "agentTurn",
            message: DEFAULT_MESSAGE,
            model: "anthropic/claude-opus-4-5",
            deliver: false,
          },
          storeEntries: {
            "agent:main:cron:job-1": {
              sessionId: "existing-session",
              updatedAt: Date.now(),
              providerOverride: "openai",
              modelOverride: "gpt-4.1-mini",
            },
          },
        });
        (expect* step3.call.provider).is("anthropic");
        (expect* step3.call.model).is("claude-opus-4-5");
      });
    });

    (deftest "provider does not leak between isolated sequential runs", async () => {
      // Run with openai, then run with no override.
      // Second run must get the default (anthropic), not leaked openai.
      await withTempHome(async (home) => {
        // Run 1: explicit openai
        const r1 = await runTurn(home, {
          jobPayload: {
            kind: "agentTurn",
            message: DEFAULT_MESSAGE,
            model: "openai/gpt-4.1-mini",
          },
        });
        (expect* r1.call.provider).is("openai");

        // Run 2: no override — must revert to default anthropic
        mock:mocked(runEmbeddedPiAgent).mockClear();
        mockEmbeddedOk();
        const r2 = await runTurn(home, {
          jobPayload: { kind: "agentTurn", message: DEFAULT_MESSAGE, deliver: false },
        });
        (expect* r2.call.provider).is("anthropic");
        (expect* r2.call.model).is("claude-opus-4-5");
      });
    });
  });

  // ------ forceNew session + stored model override interaction ------

  (deftest-group "forceNew session preserves model overrides from store", () => {
    (deftest "new isolated session inherits stored modelOverride/providerOverride", async () => {
      // Isolated cron uses forceNew=true, which creates a new sessionId.
      // The stored modelOverride/providerOverride must still be read and applied
      // (resolveCronSession spreads ...entry before overriding core fields).
      await withTempHome(async (home) => {
        const { call } = await runTurn(home, {
          jobPayload: { kind: "agentTurn", message: DEFAULT_MESSAGE, deliver: false },
          storeEntries: {
            "agent:main:cron:job-1": {
              sessionId: "old-session-id",
              updatedAt: Date.now(),
              providerOverride: "openai",
              modelOverride: "gpt-4.1-mini",
            },
          },
        });
        (expect* call.provider).is("openai");
        (expect* call.model).is("gpt-4.1-mini");
      });
    });

    (deftest "new isolated session uses default when store has no override", async () => {
      await withTempHome(async (home) => {
        const { call } = await runTurn(home, {
          jobPayload: { kind: "agentTurn", message: DEFAULT_MESSAGE, deliver: false },
          storeEntries: {
            "agent:main:cron:job-1": {
              sessionId: "old-session-id",
              updatedAt: Date.now(),
              // No providerOverride or modelOverride
            },
          },
        });
        (expect* call.provider).is("anthropic");
        (expect* call.model).is("claude-opus-4-5");
      });
    });
  });

  // ------ whitespace / empty edge cases ------

  (deftest-group "whitespace and empty model strings", () => {
    (deftest "whitespace-only model treated as unset (falls to default)", async () => {
      await withTempHome(async (home) => {
        const { call } = await runTurn(home, {
          jobPayload: { kind: "agentTurn", message: DEFAULT_MESSAGE, model: "   " },
        });
        (expect* call.provider).is("anthropic");
        (expect* call.model).is("claude-opus-4-5");
      });
    });

    (deftest "empty string model treated as unset", async () => {
      await withTempHome(async (home) => {
        const { call } = await runTurn(home, {
          jobPayload: { kind: "agentTurn", message: DEFAULT_MESSAGE, model: "" },
        });
        (expect* call.provider).is("anthropic");
        (expect* call.model).is("claude-opus-4-5");
      });
    });

    (deftest "whitespace-only session modelOverride is ignored", async () => {
      await withTempHome(async (home) => {
        const { call } = await runTurn(home, {
          jobPayload: { kind: "agentTurn", message: DEFAULT_MESSAGE, deliver: false },
          storeEntries: {
            "agent:main:cron:job-1": {
              sessionId: "old",
              updatedAt: Date.now(),
              providerOverride: "openai",
              modelOverride: "   ",
            },
          },
        });
        // Whitespace modelOverride should be ignored → default
        (expect* call.provider).is("anthropic");
        (expect* call.model).is("claude-opus-4-5");
      });
    });
  });

  // ------ config default model as string vs object ------

  (deftest-group "config model format variations", () => {
    (deftest "default model as string 'provider/model'", async () => {
      await withTempHome(async (home) => {
        const { call } = await runTurn(home, {
          cfgOverrides: {
            agents: {
              defaults: {
                model: "openai/gpt-4.1",
              },
            },
          },
          jobPayload: { kind: "agentTurn", message: DEFAULT_MESSAGE, deliver: false },
        });
        (expect* call.provider).is("openai");
        (expect* call.model).is("gpt-4.1");
      });
    });

    (deftest "default model as object with primary field", async () => {
      await withTempHome(async (home) => {
        const { call } = await runTurn(home, {
          cfgOverrides: {
            agents: {
              defaults: {
                model: { primary: "openai/gpt-4.1" },
              },
            },
          },
          jobPayload: { kind: "agentTurn", message: DEFAULT_MESSAGE, deliver: false },
        });
        (expect* call.provider).is("openai");
        (expect* call.model).is("gpt-4.1");
      });
    });

    (deftest "job override switches away from object default", async () => {
      await withTempHome(async (home) => {
        const { call } = await runTurn(home, {
          cfgOverrides: {
            agents: {
              defaults: {
                model: { primary: "openai/gpt-4.1" },
              },
            },
          },
          jobPayload: {
            kind: "agentTurn",
            message: DEFAULT_MESSAGE,
            model: "anthropic/claude-sonnet-4-5",
          },
        });
        (expect* call.provider).is("anthropic");
        (expect* call.model).is("claude-sonnet-4-5");
      });
    });
  });
});
