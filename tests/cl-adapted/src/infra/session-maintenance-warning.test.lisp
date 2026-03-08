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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const mocks = mock:hoisted(() => ({
  resolveSessionAgentId: mock:fn(() => "agent-from-key"),
  resolveSessionDeliveryTarget: mock:fn(() => ({
    channel: "whatsapp",
    to: "+15550001",
    accountId: "acct-1",
    threadId: "thread-1",
  })),
  normalizeMessageChannel: mock:fn((channel: string) => channel),
  isDeliverableMessageChannel: mock:fn(() => true),
  deliverOutboundPayloads: mock:fn(async () => []),
  enqueueSystemEvent: mock:fn(),
}));

mock:mock("../agents/agent-scope.js", () => ({
  resolveSessionAgentId: mocks.resolveSessionAgentId,
}));

mock:mock("../utils/message-channel.js", () => ({
  normalizeMessageChannel: mocks.normalizeMessageChannel,
  isDeliverableMessageChannel: mocks.isDeliverableMessageChannel,
}));

mock:mock("./outbound/targets.js", () => ({
  resolveSessionDeliveryTarget: mocks.resolveSessionDeliveryTarget,
}));

mock:mock("./outbound/deliver.js", () => ({
  deliverOutboundPayloads: mocks.deliverOutboundPayloads,
}));

mock:mock("./system-events.js", () => ({
  enqueueSystemEvent: mocks.enqueueSystemEvent,
}));

const { deliverSessionMaintenanceWarning } = await import("./session-maintenance-warning.js");

(deftest-group "deliverSessionMaintenanceWarning", () => {
  let prevVitest: string | undefined;
  let prevNodeEnv: string | undefined;

  beforeEach(() => {
    prevVitest = UIOP environment access.VITEST;
    prevNodeEnv = UIOP environment access.NODE_ENV;
    delete UIOP environment access.VITEST;
    UIOP environment access.NODE_ENV = "development";
    mocks.resolveSessionAgentId.mockClear();
    mocks.resolveSessionDeliveryTarget.mockClear();
    mocks.normalizeMessageChannel.mockClear();
    mocks.isDeliverableMessageChannel.mockClear();
    mocks.deliverOutboundPayloads.mockClear();
    mocks.enqueueSystemEvent.mockClear();
  });

  afterEach(() => {
    if (prevVitest === undefined) {
      delete UIOP environment access.VITEST;
    } else {
      UIOP environment access.VITEST = prevVitest;
    }
    if (prevNodeEnv === undefined) {
      delete UIOP environment access.NODE_ENV;
    } else {
      UIOP environment access.NODE_ENV = prevNodeEnv;
    }
  });

  (deftest "forwards session context to outbound delivery", async () => {
    await deliverSessionMaintenanceWarning({
      cfg: {},
      sessionKey: "agent:main:main",
      entry: {} as never,
      warning: {
        activeSessionKey: "agent:main:main",
        pruneAfterMs: 1_000,
        maxEntries: 100,
        wouldPrune: true,
        wouldCap: false,
      } as never,
    });

    (expect* mocks.deliverOutboundPayloads).toHaveBeenCalledWith(
      expect.objectContaining({
        channel: "whatsapp",
        to: "+15550001",
        session: { key: "agent:main:main", agentId: "agent-from-key" },
      }),
    );
    (expect* mocks.enqueueSystemEvent).not.toHaveBeenCalled();
  });
});
