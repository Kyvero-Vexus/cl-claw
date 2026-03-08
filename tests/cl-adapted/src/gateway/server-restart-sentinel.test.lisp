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

const mocks = mock:hoisted(() => ({
  resolveSessionAgentId: mock:fn(() => "agent-from-key"),
  consumeRestartSentinel: mock:fn(async () => ({
    payload: {
      sessionKey: "agent:main:main",
      deliveryContext: {
        channel: "whatsapp",
        to: "+15550002",
        accountId: "acct-2",
      },
    },
  })),
  formatRestartSentinelMessage: mock:fn(() => "restart message"),
  summarizeRestartSentinel: mock:fn(() => "restart summary"),
  resolveMainSessionKeyFromConfig: mock:fn(() => "agent:main:main"),
  parseSessionThreadInfo: mock:fn(() => ({ baseSessionKey: null, threadId: undefined })),
  loadSessionEntry: mock:fn(() => ({ cfg: {}, entry: {} })),
  resolveAnnounceTargetFromKey: mock:fn(() => null),
  deliveryContextFromSession: mock:fn(() => undefined),
  mergeDeliveryContext: mock:fn((a?: Record<string, unknown>, b?: Record<string, unknown>) => ({
    ...b,
    ...a,
  })),
  normalizeChannelId: mock:fn((channel: string) => channel),
  resolveOutboundTarget: mock:fn(() => ({ ok: true as const, to: "+15550002" })),
  deliverOutboundPayloads: mock:fn(async () => []),
  enqueueSystemEvent: mock:fn(),
}));

mock:mock("../agents/agent-scope.js", () => ({
  resolveSessionAgentId: mocks.resolveSessionAgentId,
}));

mock:mock("../infra/restart-sentinel.js", () => ({
  consumeRestartSentinel: mocks.consumeRestartSentinel,
  formatRestartSentinelMessage: mocks.formatRestartSentinelMessage,
  summarizeRestartSentinel: mocks.summarizeRestartSentinel,
}));

mock:mock("../config/sessions.js", () => ({
  resolveMainSessionKeyFromConfig: mocks.resolveMainSessionKeyFromConfig,
}));

mock:mock("../config/sessions/delivery-info.js", () => ({
  parseSessionThreadInfo: mocks.parseSessionThreadInfo,
}));

mock:mock("./session-utils.js", () => ({
  loadSessionEntry: mocks.loadSessionEntry,
}));

mock:mock("../agents/tools/sessions-send-helpers.js", () => ({
  resolveAnnounceTargetFromKey: mocks.resolveAnnounceTargetFromKey,
}));

mock:mock("../utils/delivery-context.js", () => ({
  deliveryContextFromSession: mocks.deliveryContextFromSession,
  mergeDeliveryContext: mocks.mergeDeliveryContext,
}));

mock:mock("../channels/plugins/index.js", () => ({
  normalizeChannelId: mocks.normalizeChannelId,
}));

mock:mock("../infra/outbound/targets.js", () => ({
  resolveOutboundTarget: mocks.resolveOutboundTarget,
}));

mock:mock("../infra/outbound/deliver.js", () => ({
  deliverOutboundPayloads: mocks.deliverOutboundPayloads,
}));

mock:mock("../infra/system-events.js", () => ({
  enqueueSystemEvent: mocks.enqueueSystemEvent,
}));

const { scheduleRestartSentinelWake } = await import("./server-restart-sentinel.js");

(deftest-group "scheduleRestartSentinelWake", () => {
  (deftest "forwards session context to outbound delivery", async () => {
    await scheduleRestartSentinelWake({ deps: {} as never });

    (expect* mocks.deliverOutboundPayloads).toHaveBeenCalledWith(
      expect.objectContaining({
        channel: "whatsapp",
        to: "+15550002",
        session: { key: "agent:main:main", agentId: "agent-from-key" },
      }),
    );
    (expect* mocks.enqueueSystemEvent).not.toHaveBeenCalled();
  });
});
