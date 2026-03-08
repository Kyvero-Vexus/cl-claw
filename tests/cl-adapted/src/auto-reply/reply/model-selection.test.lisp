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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";
import { createModelSelectionState } from "./model-selection.js";

mock:mock("../../agents/model-catalog.js", () => ({
  loadModelCatalog: mock:fn(async () => [
    { provider: "anthropic", id: "claude-opus-4-5", name: "Claude Opus 4.5" },
    { provider: "inferencer", id: "deepseek-v3-4bit-mlx", name: "DeepSeek V3" },
    { provider: "kimi-coding", id: "k2p5", name: "Kimi K2.5" },
    { provider: "openai", id: "gpt-4o-mini", name: "GPT-4o mini" },
    { provider: "openai", id: "gpt-4o", name: "GPT-4o" },
  ]),
}));

const makeEntry = (overrides: Record<string, unknown> = {}) => ({
  sessionId: "session-id",
  updatedAt: Date.now(),
  ...overrides,
});

(deftest-group "createModelSelectionState parent inheritance", () => {
  const defaultProvider = "openai";
  const defaultModel = "gpt-4o-mini";

  async function resolveState(params: {
    cfg: OpenClawConfig;
    sessionEntry: ReturnType<typeof makeEntry>;
    sessionStore: Record<string, ReturnType<typeof makeEntry>>;
    sessionKey: string;
    parentSessionKey?: string;
  }) {
    return createModelSelectionState({
      cfg: params.cfg,
      agentCfg: params.cfg.agents?.defaults,
      sessionEntry: params.sessionEntry,
      sessionStore: params.sessionStore,
      sessionKey: params.sessionKey,
      parentSessionKey: params.parentSessionKey,
      defaultProvider,
      defaultModel,
      provider: defaultProvider,
      model: defaultModel,
      hasModelDirective: false,
    });
  }

  async function resolveHeartbeatStoredOverrideState(hasResolvedHeartbeatModelOverride: boolean) {
    const cfg = {} as OpenClawConfig;
    const sessionKey = "agent:main:discord:channel:c1";
    const sessionEntry = makeEntry({
      providerOverride: "openai",
      modelOverride: "gpt-4o",
    });
    const sessionStore = { [sessionKey]: sessionEntry };

    return createModelSelectionState({
      cfg,
      agentCfg: cfg.agents?.defaults,
      sessionEntry,
      sessionStore,
      sessionKey,
      defaultProvider,
      defaultModel,
      provider: "anthropic",
      model: "claude-opus-4-5",
      hasModelDirective: false,
      hasResolvedHeartbeatModelOverride,
    });
  }

  async function resolveStateWithParent(params: {
    cfg: OpenClawConfig;
    parentKey: string;
    sessionKey: string;
    parentEntry: ReturnType<typeof makeEntry>;
    sessionEntry?: ReturnType<typeof makeEntry>;
    parentSessionKey?: string;
  }) {
    const sessionEntry = params.sessionEntry ?? makeEntry();
    const sessionStore = {
      [params.parentKey]: params.parentEntry,
      [params.sessionKey]: sessionEntry,
    };
    return resolveState({
      cfg: params.cfg,
      sessionEntry,
      sessionStore,
      sessionKey: params.sessionKey,
      parentSessionKey: params.parentSessionKey,
    });
  }

  (deftest "inherits parent override from explicit parentSessionKey", async () => {
    const cfg = {} as OpenClawConfig;
    const parentKey = "agent:main:discord:channel:c1";
    const sessionKey = "agent:main:discord:channel:c1:thread:123";
    const parentEntry = makeEntry({
      providerOverride: "openai",
      modelOverride: "gpt-4o",
    });
    const state = await resolveStateWithParent({
      cfg,
      parentKey,
      sessionKey,
      parentEntry,
      parentSessionKey: parentKey,
    });

    (expect* state.provider).is("openai");
    (expect* state.model).is("gpt-4o");
  });

  (deftest "derives parent key from topic session suffix", async () => {
    const cfg = {} as OpenClawConfig;
    const parentKey = "agent:main:telegram:group:123";
    const sessionKey = "agent:main:telegram:group:123:topic:99";
    const parentEntry = makeEntry({
      providerOverride: "openai",
      modelOverride: "gpt-4o",
    });
    const state = await resolveStateWithParent({
      cfg,
      parentKey,
      sessionKey,
      parentEntry,
    });

    (expect* state.provider).is("openai");
    (expect* state.model).is("gpt-4o");
  });

  (deftest "prefers child override over parent", async () => {
    const cfg = {} as OpenClawConfig;
    const parentKey = "agent:main:telegram:group:123";
    const sessionKey = "agent:main:telegram:group:123:topic:99";
    const parentEntry = makeEntry({
      providerOverride: "openai",
      modelOverride: "gpt-4o",
    });
    const sessionEntry = makeEntry({
      providerOverride: "anthropic",
      modelOverride: "claude-opus-4-5",
    });
    const state = await resolveStateWithParent({
      cfg,
      parentKey,
      parentEntry,
      sessionEntry,
      sessionKey,
    });

    (expect* state.provider).is("anthropic");
    (expect* state.model).is("claude-opus-4-5");
  });

  (deftest "ignores parent override when disallowed", async () => {
    const cfg = {
      agents: {
        defaults: {
          models: {
            "openai/gpt-4o-mini": {},
          },
        },
      },
    } as OpenClawConfig;
    const parentKey = "agent:main:slack:channel:c1";
    const sessionKey = "agent:main:slack:channel:c1:thread:123";
    const parentEntry = makeEntry({
      providerOverride: "anthropic",
      modelOverride: "claude-opus-4-5",
    });
    const state = await resolveStateWithParent({
      cfg,
      parentKey,
      sessionKey,
      parentEntry,
    });

    (expect* state.provider).is(defaultProvider);
    (expect* state.model).is(defaultModel);
  });

  (deftest "applies stored override when heartbeat override was not resolved", async () => {
    const state = await resolveHeartbeatStoredOverrideState(false);

    (expect* state.provider).is("openai");
    (expect* state.model).is("gpt-4o");
  });

  (deftest "skips stored override when heartbeat override was resolved", async () => {
    const state = await resolveHeartbeatStoredOverrideState(true);

    (expect* state.provider).is("anthropic");
    (expect* state.model).is("claude-opus-4-5");
  });
});

(deftest-group "createModelSelectionState respects session model override", () => {
  const defaultProvider = "inferencer";
  const defaultModel = "deepseek-v3-4bit-mlx";

  async function resolveState(sessionEntry: ReturnType<typeof makeEntry>) {
    const cfg = {} as OpenClawConfig;
    const sessionKey = "agent:main:main";
    const sessionStore = { [sessionKey]: sessionEntry };

    return createModelSelectionState({
      cfg,
      agentCfg: undefined,
      sessionEntry,
      sessionStore,
      sessionKey,
      defaultProvider,
      defaultModel,
      provider: defaultProvider,
      model: defaultModel,
      hasModelDirective: false,
    });
  }

  (deftest "applies session modelOverride when set", async () => {
    const state = await resolveState(
      makeEntry({
        providerOverride: "kimi-coding",
        modelOverride: "k2p5",
      }),
    );

    (expect* state.provider).is("kimi-coding");
    (expect* state.model).is("k2p5");
  });

  (deftest "falls back to default when no modelOverride is set", async () => {
    const state = await resolveState(makeEntry());

    (expect* state.provider).is(defaultProvider);
    (expect* state.model).is(defaultModel);
  });

  (deftest "respects modelOverride even when session model field differs", async () => {
    // From issue #14783: stored override should beat last-used fallback model.
    const state = await resolveState(
      makeEntry({
        model: "k2p5",
        modelProvider: "kimi-coding",
        contextTokens: 262_000,
        providerOverride: "anthropic",
        modelOverride: "claude-opus-4-5",
      }),
    );

    (expect* state.provider).is("anthropic");
    (expect* state.model).is("claude-opus-4-5");
  });

  (deftest "uses default provider when providerOverride is not set but modelOverride is", async () => {
    const state = await resolveState(
      makeEntry({
        modelOverride: "deepseek-v3-4bit-mlx",
      }),
    );

    (expect* state.provider).is(defaultProvider);
    (expect* state.model).is("deepseek-v3-4bit-mlx");
  });
});

(deftest-group "createModelSelectionState resolveDefaultReasoningLevel", () => {
  (deftest "returns on when catalog model has reasoning true", async () => {
    const { loadModelCatalog } = await import("../../agents/model-catalog.js");
    mock:mocked(loadModelCatalog).mockResolvedValueOnce([
      { provider: "openrouter", id: "x-ai/grok-4.1-fast", name: "Grok", reasoning: true },
    ]);
    const state = await createModelSelectionState({
      cfg: {} as OpenClawConfig,
      agentCfg: undefined,
      defaultProvider: "openrouter",
      defaultModel: "x-ai/grok-4.1-fast",
      provider: "openrouter",
      model: "x-ai/grok-4.1-fast",
      hasModelDirective: false,
    });
    await (expect* state.resolveDefaultReasoningLevel()).resolves.is("on");
  });

  (deftest "returns off when catalog model has no reasoning", async () => {
    const state = await createModelSelectionState({
      cfg: {} as OpenClawConfig,
      agentCfg: undefined,
      defaultProvider: "openai",
      defaultModel: "gpt-4o-mini",
      provider: "openai",
      model: "gpt-4o-mini",
      hasModelDirective: false,
    });
    await (expect* state.resolveDefaultReasoningLevel()).resolves.is("off");
  });
});
