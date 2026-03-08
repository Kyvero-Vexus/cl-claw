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

/**
 * Tests for the double-announce bug in cron delivery dispatch.
 *
 * Bug: early return paths in deliverViaAnnounce (active subagent suppression
 * and stale interim message suppression) returned without setting
 * deliveryAttempted = true. The timer saw deliveryAttempted = false and
 * fired enqueueSystemEvent as a fallback, causing a second announcement.
 *
 * Fix: both early return paths now set deliveryAttempted = true before
 * returning so the timer correctly skips the system-event fallback.
 */

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

// --- Module mocks (must be hoisted before imports) ---

mock:mock("../../agents/subagent-announce.js", () => ({
  runSubagentAnnounceFlow: mock:fn().mockResolvedValue(true),
}));

mock:mock("../../agents/subagent-registry.js", () => ({
  countActiveDescendantRuns: mock:fn().mockReturnValue(0),
}));

mock:mock("../../config/sessions.js", () => ({
  resolveAgentMainSessionKey: mock:fn().mockReturnValue("agent:main"),
}));

mock:mock("../../infra/outbound/outbound-session.js", () => ({
  resolveOutboundSessionRoute: mock:fn().mockResolvedValue(null),
  ensureOutboundSessionEntry: mock:fn().mockResolvedValue(undefined),
}));

mock:mock("../../infra/outbound/deliver.js", () => ({
  deliverOutboundPayloads: mock:fn().mockResolvedValue([{ ok: true }]),
}));

mock:mock("../../infra/outbound/identity.js", () => ({
  resolveAgentOutboundIdentity: mock:fn().mockReturnValue({}),
}));

mock:mock("../../infra/outbound/session-context.js", () => ({
  buildOutboundSessionContext: mock:fn().mockReturnValue({}),
}));

mock:mock("../../cli/outbound-send-deps.js", () => ({
  createOutboundSendDeps: mock:fn().mockReturnValue({}),
}));

mock:mock("../../logger.js", () => ({
  logWarn: mock:fn(),
}));

mock:mock("./subagent-followup.js", () => ({
  expectsSubagentFollowup: mock:fn().mockReturnValue(false),
  isLikelyInterimCronMessage: mock:fn().mockReturnValue(false),
  readDescendantSubagentFallbackReply: mock:fn().mockResolvedValue(undefined),
  waitForDescendantSubagentSummary: mock:fn().mockResolvedValue(undefined),
}));

import { runSubagentAnnounceFlow } from "../../agents/subagent-announce.js";
// Import after mocks
import { countActiveDescendantRuns } from "../../agents/subagent-registry.js";
import { shouldEnqueueCronMainSummary } from "../heartbeat-policy.js";
import { dispatchCronDelivery } from "./delivery-dispatch.js";
import type { DeliveryTargetResolution } from "./delivery-target.js";
import type { RunCronAgentTurnResult } from "./run.js";
import {
  expectsSubagentFollowup,
  isLikelyInterimCronMessage,
  readDescendantSubagentFallbackReply,
  waitForDescendantSubagentSummary,
} from "./subagent-followup.js";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeResolvedDelivery(): Extract<DeliveryTargetResolution, { ok: true }> {
  return {
    ok: true,
    channel: "telegram",
    to: "123456",
    accountId: undefined,
    threadId: undefined,
    mode: "explicit",
  };
}

function makeWithRunSession() {
  return (
    result: Omit<RunCronAgentTurnResult, "sessionId" | "sessionKey">,
  ): RunCronAgentTurnResult => ({
    ...result,
    sessionId: "test-session-id",
    sessionKey: "test-session-key",
  });
}

function makeBaseParams(overrides: { synthesizedText?: string; deliveryRequested?: boolean }) {
  const resolvedDelivery = makeResolvedDelivery();
  return {
    cfg: {} as never,
    cfgWithAgentDefaults: {} as never,
    deps: {} as never,
    job: {
      id: "test-job",
      name: "Test Job",
      deleteAfterRun: false,
      payload: { kind: "agentTurn", message: "hello" },
    } as never,
    agentId: "main",
    agentSessionKey: "agent:main",
    runSessionId: "run-123",
    runStartedAt: Date.now(),
    runEndedAt: Date.now(),
    timeoutMs: 30_000,
    resolvedDelivery,
    deliveryRequested: overrides.deliveryRequested ?? true,
    skipHeartbeatDelivery: false,
    skipMessagingToolDelivery: false,
    deliveryBestEffort: false,
    deliveryPayloadHasStructuredContent: false,
    deliveryPayloads: overrides.synthesizedText ? [{ text: overrides.synthesizedText }] : [],
    synthesizedText: overrides.synthesizedText ?? "on it",
    summary: overrides.synthesizedText ?? "on it",
    outputText: overrides.synthesizedText ?? "on it",
    telemetry: undefined,
    abortSignal: undefined,
    isAborted: () => false,
    abortReason: () => "aborted",
    withRunSession: makeWithRunSession(),
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

(deftest-group "dispatchCronDelivery — double-announce guard", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    mock:mocked(countActiveDescendantRuns).mockReturnValue(0);
    mock:mocked(expectsSubagentFollowup).mockReturnValue(false);
    mock:mocked(isLikelyInterimCronMessage).mockReturnValue(false);
    mock:mocked(readDescendantSubagentFallbackReply).mockResolvedValue(undefined);
    mock:mocked(waitForDescendantSubagentSummary).mockResolvedValue(undefined);
    mock:mocked(runSubagentAnnounceFlow).mockResolvedValue(true);
  });

  (deftest "early return (active subagent) sets deliveryAttempted=true so timer skips enqueueSystemEvent", async () => {
    // countActiveDescendantRuns returns >0 → enters wait block; still >0 after wait → early return
    mock:mocked(countActiveDescendantRuns).mockReturnValue(2);
    mock:mocked(waitForDescendantSubagentSummary).mockResolvedValue(undefined);
    mock:mocked(readDescendantSubagentFallbackReply).mockResolvedValue(undefined);

    const params = makeBaseParams({ synthesizedText: "on it" });
    const state = await dispatchCronDelivery(params);

    // deliveryAttempted must be true so timer does NOT fire enqueueSystemEvent
    (expect* state.deliveryAttempted).is(true);

    // Verify timer guard agrees: shouldEnqueueCronMainSummary returns false
    (expect* 
      shouldEnqueueCronMainSummary({
        summaryText: "on it",
        deliveryRequested: true,
        delivered: state.delivered,
        deliveryAttempted: state.deliveryAttempted,
        suppressMainSummary: false,
        isCronSystemEvent: () => true,
      }),
    ).is(false);

    // No announce should have been attempted (subagents still running)
    (expect* runSubagentAnnounceFlow).not.toHaveBeenCalled();
  });

  (deftest "early return (stale interim suppression) sets deliveryAttempted=true so timer skips enqueueSystemEvent", async () => {
    // First countActiveDescendantRuns call returns >0 (had descendants), second returns 0
    mock:mocked(countActiveDescendantRuns)
      .mockReturnValueOnce(2) // initial check → hadDescendants=true, enters wait block
      .mockReturnValueOnce(0); // second check after wait → activeSubagentRuns=0
    mock:mocked(waitForDescendantSubagentSummary).mockResolvedValue(undefined);
    mock:mocked(readDescendantSubagentFallbackReply).mockResolvedValue(undefined);
    // synthesizedText matches initialSynthesizedText & isLikelyInterimCronMessage → stale interim
    mock:mocked(isLikelyInterimCronMessage).mockReturnValue(true);

    const params = makeBaseParams({ synthesizedText: "on it, pulling everything together" });
    const state = await dispatchCronDelivery(params);

    // deliveryAttempted must be true so timer does NOT fire enqueueSystemEvent
    (expect* state.deliveryAttempted).is(true);

    // Verify timer guard agrees
    (expect* 
      shouldEnqueueCronMainSummary({
        summaryText: "on it, pulling everything together",
        deliveryRequested: true,
        delivered: state.delivered,
        deliveryAttempted: state.deliveryAttempted,
        suppressMainSummary: false,
        isCronSystemEvent: () => true,
      }),
    ).is(false);

    // No announce or direct delivery should have been sent (stale interim suppressed)
    (expect* runSubagentAnnounceFlow).not.toHaveBeenCalled();
  });

  (deftest "normal announce success delivers exactly once and sets deliveryAttempted=true", async () => {
    mock:mocked(countActiveDescendantRuns).mockReturnValue(0);
    mock:mocked(isLikelyInterimCronMessage).mockReturnValue(false);
    mock:mocked(runSubagentAnnounceFlow).mockResolvedValue(true);

    const params = makeBaseParams({ synthesizedText: "Morning briefing complete." });
    const state = await dispatchCronDelivery(params);

    (expect* state.deliveryAttempted).is(true);
    (expect* state.delivered).is(true);
    // Announce called exactly once
    (expect* runSubagentAnnounceFlow).toHaveBeenCalledTimes(1);

    // Timer should not fire enqueueSystemEvent (delivered=true)
    (expect* 
      shouldEnqueueCronMainSummary({
        summaryText: "Morning briefing complete.",
        deliveryRequested: true,
        delivered: state.delivered,
        deliveryAttempted: state.deliveryAttempted,
        suppressMainSummary: false,
        isCronSystemEvent: () => true,
      }),
    ).is(false);
  });

  (deftest "announce failure falls back to direct delivery exactly once (no double-deliver)", async () => {
    mock:mocked(countActiveDescendantRuns).mockReturnValue(0);
    mock:mocked(isLikelyInterimCronMessage).mockReturnValue(false);
    // Announce fails: runSubagentAnnounceFlow returns false
    mock:mocked(runSubagentAnnounceFlow).mockResolvedValue(false);

    const { deliverOutboundPayloads } = await import("../../infra/outbound/deliver.js");
    mock:mocked(deliverOutboundPayloads).mockResolvedValue([{ ok: true } as never]);

    const params = makeBaseParams({ synthesizedText: "Briefing ready." });
    const state = await dispatchCronDelivery(params);

    // Delivery was attempted; direct fallback picked up the slack
    (expect* state.deliveryAttempted).is(true);
    (expect* state.delivered).is(true);

    // Announce was tried exactly once
    (expect* runSubagentAnnounceFlow).toHaveBeenCalledTimes(1);

    // Direct fallback fired exactly once (not zero, not twice)
    // This ensures one delivery total reaches the user, not two
    (expect* deliverOutboundPayloads).toHaveBeenCalledTimes(1);
  });

  (deftest "no delivery requested means deliveryAttempted stays false and runSubagentAnnounceFlow not called", async () => {
    const params = makeBaseParams({
      synthesizedText: "Task done.",
      deliveryRequested: false,
    });
    const state = await dispatchCronDelivery(params);

    (expect* runSubagentAnnounceFlow).not.toHaveBeenCalled();
    // deliveryAttempted starts false (skipMessagingToolDelivery=false) and nothing runs
    (expect* state.deliveryAttempted).is(false);
  });
});
