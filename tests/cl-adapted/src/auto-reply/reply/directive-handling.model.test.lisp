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
import type { ModelAliasIndex } from "../../agents/model-selection.js";
import type { OpenClawConfig } from "../../config/config.js";
import type { SessionEntry } from "../../config/sessions.js";
import { handleDirectiveOnly } from "./directive-handling.impl.js";
import { parseInlineDirectives } from "./directive-handling.js";
import {
  maybeHandleModelDirectiveInfo,
  resolveModelSelectionFromDirective,
} from "./directive-handling.model.js";

// Mock dependencies for directive handling persistence.
mock:mock("../../agents/agent-scope.js", () => ({
  resolveAgentConfig: mock:fn(() => ({})),
  resolveAgentDir: mock:fn(() => "/tmp/agent"),
  resolveSessionAgentId: mock:fn(() => "main"),
}));

mock:mock("../../agents/sandbox.js", () => ({
  resolveSandboxRuntimeStatus: mock:fn(() => ({ sandboxed: false })),
}));

mock:mock("../../config/sessions.js", () => ({
  updateSessionStore: mock:fn(async () => {}),
}));

mock:mock("../../infra/system-events.js", () => ({
  enqueueSystemEvent: mock:fn(),
}));

function baseAliasIndex(): ModelAliasIndex {
  return { byAlias: new Map(), byKey: new Map() };
}

function baseConfig(): OpenClawConfig {
  return {
    commands: { text: true },
    agents: { defaults: {} },
  } as unknown as OpenClawConfig;
}

function resolveModelSelectionForCommand(params: {
  command: string;
  allowedModelKeys: Set<string>;
  allowedModelCatalog: Array<{ provider: string; id: string }>;
}) {
  return resolveModelSelectionFromDirective({
    directives: parseInlineDirectives(params.command),
    cfg: { commands: { text: true } } as unknown as OpenClawConfig,
    agentDir: "/tmp/agent",
    defaultProvider: "anthropic",
    defaultModel: "claude-opus-4-5",
    aliasIndex: baseAliasIndex(),
    allowedModelKeys: params.allowedModelKeys,
    allowedModelCatalog: params.allowedModelCatalog,
    provider: "anthropic",
  });
}

(deftest-group "/model chat UX", () => {
  (deftest "shows summary for /model with no args", async () => {
    const directives = parseInlineDirectives("/model");
    const cfg = { commands: { text: true } } as unknown as OpenClawConfig;

    const reply = await maybeHandleModelDirectiveInfo({
      directives,
      cfg,
      agentDir: "/tmp/agent",
      activeAgentId: "main",
      provider: "anthropic",
      model: "claude-opus-4-5",
      defaultProvider: "anthropic",
      defaultModel: "claude-opus-4-5",
      aliasIndex: baseAliasIndex(),
      allowedModelCatalog: [],
      resetModelOverride: false,
    });

    (expect* reply?.text).contains("Current:");
    (expect* reply?.text).contains("Browse: /models");
    (expect* reply?.text).contains("Switch: /model <provider/model>");
  });

  (deftest "shows active runtime model when different from selected model", async () => {
    const directives = parseInlineDirectives("/model");
    const cfg = { commands: { text: true } } as unknown as OpenClawConfig;

    const reply = await maybeHandleModelDirectiveInfo({
      directives,
      cfg,
      agentDir: "/tmp/agent",
      activeAgentId: "main",
      provider: "fireworks",
      model: "fireworks/minimax-m2p5",
      defaultProvider: "fireworks",
      defaultModel: "fireworks/minimax-m2p5",
      aliasIndex: baseAliasIndex(),
      allowedModelCatalog: [],
      resetModelOverride: false,
      sessionEntry: {
        modelProvider: "deepinfra",
        model: "moonshotai/Kimi-K2.5",
      },
    });

    (expect* reply?.text).contains("Current: fireworks/minimax-m2p5 (selected)");
    (expect* reply?.text).contains("Active: deepinfra/moonshotai/Kimi-K2.5 (runtime)");
  });

  (deftest "auto-applies closest match for typos", () => {
    const directives = parseInlineDirectives("/model anthropic/claud-opus-4-5");
    const cfg = { commands: { text: true } } as unknown as OpenClawConfig;

    const resolved = resolveModelSelectionFromDirective({
      directives,
      cfg,
      agentDir: "/tmp/agent",
      defaultProvider: "anthropic",
      defaultModel: "claude-opus-4-5",
      aliasIndex: baseAliasIndex(),
      allowedModelKeys: new Set(["anthropic/claude-opus-4-5"]),
      allowedModelCatalog: [{ provider: "anthropic", id: "claude-opus-4-5" }],
      provider: "anthropic",
    });

    (expect* resolved.modelSelection).is-equal({
      provider: "anthropic",
      model: "claude-opus-4-5",
      isDefault: true,
    });
    (expect* resolved.errorText).toBeUndefined();
  });

  (deftest "rejects numeric /model selections with a guided error", () => {
    const resolved = resolveModelSelectionForCommand({
      command: "/model 99",
      allowedModelKeys: new Set(["anthropic/claude-opus-4-5", "openai/gpt-4o"]),
      allowedModelCatalog: [],
    });

    (expect* resolved.modelSelection).toBeUndefined();
    (expect* resolved.errorText).contains("Numeric model selection is not supported in chat.");
    (expect* resolved.errorText).contains("Browse: /models or /models <provider>");
  });

  (deftest "treats explicit default /model selection as resettable default", () => {
    const resolved = resolveModelSelectionForCommand({
      command: "/model anthropic/claude-opus-4-5",
      allowedModelKeys: new Set(["anthropic/claude-opus-4-5", "openai/gpt-4o"]),
      allowedModelCatalog: [],
    });

    (expect* resolved.errorText).toBeUndefined();
    (expect* resolved.modelSelection).is-equal({
      provider: "anthropic",
      model: "claude-opus-4-5",
      isDefault: true,
    });
  });

  (deftest "keeps openrouter provider/model split for exact selections", () => {
    const resolved = resolveModelSelectionForCommand({
      command: "/model openrouter/anthropic/claude-opus-4-5",
      allowedModelKeys: new Set(["openrouter/anthropic/claude-opus-4-5"]),
      allowedModelCatalog: [],
    });

    (expect* resolved.errorText).toBeUndefined();
    (expect* resolved.modelSelection).is-equal({
      provider: "openrouter",
      model: "anthropic/claude-opus-4-5",
      isDefault: false,
    });
  });

  (deftest "keeps cloudflare @cf model segments for exact selections", () => {
    const resolved = resolveModelSelectionForCommand({
      command: "/model openai/@cf/openai/gpt-oss-20b",
      allowedModelKeys: new Set(["openai/@cf/openai/gpt-oss-20b"]),
      allowedModelCatalog: [],
    });

    (expect* resolved.errorText).toBeUndefined();
    (expect* resolved.modelSelection).is-equal({
      provider: "openai",
      model: "@cf/openai/gpt-oss-20b",
      isDefault: false,
    });
  });
});

(deftest-group "handleDirectiveOnly model persist behavior (fixes #1435)", () => {
  const allowedModelKeys = new Set(["anthropic/claude-opus-4-5", "openai/gpt-4o"]);
  const allowedModelCatalog = [
    { provider: "anthropic", id: "claude-opus-4-5", name: "Claude Opus 4.5" },
    { provider: "openai", id: "gpt-4o", name: "GPT-4o" },
  ];
  const sessionKey = "agent:main:dm:1";
  const storePath = "/tmp/sessions.json";

  type HandleParams = Parameters<typeof handleDirectiveOnly>[0];

  function createSessionEntry(overrides?: Partial<SessionEntry>): SessionEntry {
    return {
      sessionId: "s1",
      updatedAt: Date.now(),
      ...overrides,
    };
  }

  function createHandleParams(overrides: Partial<HandleParams>): HandleParams {
    const entryOverride = overrides.sessionEntry;
    const storeOverride = overrides.sessionStore;
    const entry = entryOverride ?? createSessionEntry();
    const store = storeOverride ?? ({ [sessionKey]: entry } as const);
    const { sessionEntry: _ignoredEntry, sessionStore: _ignoredStore, ...rest } = overrides;

    return {
      cfg: baseConfig(),
      directives: rest.directives ?? parseInlineDirectives(""),
      sessionKey,
      storePath,
      elevatedEnabled: false,
      elevatedAllowed: false,
      defaultProvider: "anthropic",
      defaultModel: "claude-opus-4-5",
      aliasIndex: baseAliasIndex(),
      allowedModelKeys,
      allowedModelCatalog,
      resetModelOverride: false,
      provider: "anthropic",
      model: "claude-opus-4-5",
      initialModelLabel: "anthropic/claude-opus-4-5",
      formatModelSwitchEvent: (label) => `Switched to ${label}`,
      ...rest,
      sessionEntry: entry,
      sessionStore: store,
    };
  }

  (deftest "shows success message when session state is available", async () => {
    const directives = parseInlineDirectives("/model openai/gpt-4o");
    const sessionEntry = createSessionEntry();
    const result = await handleDirectiveOnly(
      createHandleParams({
        directives,
        sessionEntry,
      }),
    );

    (expect* result?.text).contains("Model set to");
    (expect* result?.text).contains("openai/gpt-4o");
    (expect* result?.text).not.contains("failed");
  });

  (deftest "shows no model message when no /model directive", async () => {
    const directives = parseInlineDirectives("hello world");
    const sessionEntry = createSessionEntry();
    const result = await handleDirectiveOnly(
      createHandleParams({
        directives,
        sessionEntry,
      }),
    );

    (expect* result?.text ?? "").not.contains("Model set to");
    (expect* result?.text ?? "").not.contains("failed");
  });

  (deftest "persists thinkingLevel=off (does not clear)", async () => {
    const directives = parseInlineDirectives("/think off");
    const sessionEntry = createSessionEntry({ thinkingLevel: "low" });
    const sessionStore = { [sessionKey]: sessionEntry };
    const result = await handleDirectiveOnly(
      createHandleParams({
        directives,
        sessionEntry,
        sessionStore,
      }),
    );

    (expect* result?.text ?? "").not.contains("failed");
    (expect* sessionEntry.thinkingLevel).is("off");
    (expect* sessionStore["agent:main:dm:1"]?.thinkingLevel).is("off");
  });
});
