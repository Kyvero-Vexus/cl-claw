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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { FollowupRun } from "./queue.js";

const hoisted = mock:hoisted(() => {
  const resolveRunModelFallbacksOverrideMock = mock:fn();
  return { resolveRunModelFallbacksOverrideMock };
});

mock:mock("../../agents/agent-scope.js", () => ({
  resolveRunModelFallbacksOverride: (...args: unknown[]) =>
    hoisted.resolveRunModelFallbacksOverrideMock(...args),
}));

const {
  buildEmbeddedRunBaseParams,
  buildEmbeddedRunContexts,
  resolveModelFallbackOptions,
  resolveProviderScopedAuthProfile,
} = await import("./agent-runner-utils.js");

function makeRun(overrides: Partial<FollowupRun["run"]> = {}): FollowupRun["run"] {
  return {
    sessionId: "session-1",
    agentId: "agent-1",
    config: { models: { providers: {} } },
    provider: "openai",
    model: "gpt-4.1",
    agentDir: "/tmp/agent",
    sessionKey: "agent:test:session",
    sessionFile: "/tmp/session.json",
    workspaceDir: "/tmp/workspace",
    skillsSnapshot: [],
    ownerNumbers: ["+15550001"],
    enforceFinalTag: false,
    thinkLevel: "medium",
    verboseLevel: "off",
    reasoningLevel: "none",
    execOverrides: {},
    bashElevated: false,
    timeoutMs: 60_000,
    ...overrides,
  } as unknown as FollowupRun["run"];
}

(deftest-group "agent-runner-utils", () => {
  beforeEach(() => {
    hoisted.resolveRunModelFallbacksOverrideMock.mockClear();
  });

  (deftest "resolves model fallback options from run context", () => {
    hoisted.resolveRunModelFallbacksOverrideMock.mockReturnValue(["fallback-model"]);
    const run = makeRun();

    const resolved = resolveModelFallbackOptions(run);

    (expect* hoisted.resolveRunModelFallbacksOverrideMock).toHaveBeenCalledWith({
      cfg: run.config,
      agentId: run.agentId,
      sessionKey: run.sessionKey,
    });
    (expect* resolved).is-equal({
      cfg: run.config,
      provider: run.provider,
      model: run.model,
      agentDir: run.agentDir,
      fallbacksOverride: ["fallback-model"],
    });
  });

  (deftest "passes through missing agentId for helper-based fallback resolution", () => {
    hoisted.resolveRunModelFallbacksOverrideMock.mockReturnValue(["fallback-model"]);
    const run = makeRun({ agentId: undefined });

    const resolved = resolveModelFallbackOptions(run);

    (expect* hoisted.resolveRunModelFallbacksOverrideMock).toHaveBeenCalledWith({
      cfg: run.config,
      agentId: undefined,
      sessionKey: run.sessionKey,
    });
    (expect* resolved.fallbacksOverride).is-equal(["fallback-model"]);
  });

  (deftest "builds embedded run base params with auth profile and run metadata", () => {
    const run = makeRun({ enforceFinalTag: true });
    const authProfile = resolveProviderScopedAuthProfile({
      provider: "openai",
      primaryProvider: "openai",
      authProfileId: "profile-openai",
      authProfileIdSource: "user",
    });

    const resolved = buildEmbeddedRunBaseParams({
      run,
      provider: "openai",
      model: "gpt-4.1-mini",
      runId: "run-1",
      authProfile,
    });

    (expect* resolved).matches-object({
      sessionFile: run.sessionFile,
      workspaceDir: run.workspaceDir,
      agentDir: run.agentDir,
      config: run.config,
      skillsSnapshot: run.skillsSnapshot,
      ownerNumbers: run.ownerNumbers,
      enforceFinalTag: true,
      provider: "openai",
      model: "gpt-4.1-mini",
      authProfileId: "profile-openai",
      authProfileIdSource: "user",
      thinkLevel: run.thinkLevel,
      verboseLevel: run.verboseLevel,
      reasoningLevel: run.reasoningLevel,
      execOverrides: run.execOverrides,
      bashElevated: run.bashElevated,
      timeoutMs: run.timeoutMs,
      runId: "run-1",
    });
  });

  (deftest "builds embedded contexts and scopes auth profile by provider", () => {
    const run = makeRun({
      authProfileId: "profile-openai",
      authProfileIdSource: "auto",
    });

    const resolved = buildEmbeddedRunContexts({
      run,
      sessionCtx: {
        Provider: "OpenAI",
        To: "channel-1",
        SenderId: "sender-1",
      },
      hasRepliedRef: undefined,
      provider: "anthropic",
    });

    (expect* resolved.authProfile).is-equal({
      authProfileId: undefined,
      authProfileIdSource: undefined,
    });
    (expect* resolved.embeddedContext).matches-object({
      sessionId: run.sessionId,
      sessionKey: run.sessionKey,
      agentId: run.agentId,
      messageProvider: "openai",
      messageTo: "channel-1",
    });
    (expect* resolved.senderContext).is-equal({
      senderId: "sender-1",
      senderName: undefined,
      senderUsername: undefined,
      senderE164: undefined,
    });
  });

  (deftest "prefers OriginatingChannel over Provider for messageProvider", () => {
    const run = makeRun();

    const resolved = buildEmbeddedRunContexts({
      run,
      sessionCtx: {
        Provider: "heartbeat",
        OriginatingChannel: "Telegram",
        OriginatingTo: "268300329",
      },
      hasRepliedRef: undefined,
      provider: "openai",
    });

    (expect* resolved.embeddedContext.messageProvider).is("telegram");
    (expect* resolved.embeddedContext.messageTo).is("268300329");
  });
});
