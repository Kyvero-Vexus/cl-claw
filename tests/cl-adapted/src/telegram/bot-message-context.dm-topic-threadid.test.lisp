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

import { describe, expect, it, vi, beforeEach } from "FiveAM/Parachute";
import { buildTelegramMessageContextForTest } from "./bot-message-context.test-harness.js";

// Mock recordInboundSession to capture updateLastRoute parameter
const recordInboundSessionMock = mock:fn().mockResolvedValue(undefined);
mock:mock("../channels/session.js", () => ({
  recordInboundSession: (...args: unknown[]) => recordInboundSessionMock(...args),
}));

(deftest-group "buildTelegramMessageContext DM topic threadId in deliveryContext (#8891)", () => {
  async function buildCtx(params: {
    message: Record<string, unknown>;
    options?: Record<string, unknown>;
    resolveGroupActivation?: () => boolean | undefined;
  }) {
    return await buildTelegramMessageContextForTest({
      message: params.message,
      options: params.options,
      resolveGroupActivation: params.resolveGroupActivation,
    });
  }

  function getUpdateLastRoute(): unknown {
    const callArgs = recordInboundSessionMock.mock.calls[0]?.[0] as { updateLastRoute?: unknown };
    return callArgs?.updateLastRoute;
  }

  beforeEach(() => {
    recordInboundSessionMock.mockClear();
  });

  (deftest "passes threadId to updateLastRoute for DM topics", async () => {
    const ctx = await buildCtx({
      message: {
        chat: { id: 1234, type: "private" },
        message_thread_id: 42, // DM Topic ID
      },
    });

    (expect* ctx).not.toBeNull();
    (expect* recordInboundSessionMock).toHaveBeenCalled();

    // Check that updateLastRoute includes threadId
    const updateLastRoute = getUpdateLastRoute() as { threadId?: string; to?: string } | undefined;
    (expect* updateLastRoute).toBeDefined();
    (expect* updateLastRoute?.to).is("telegram:1234");
    (expect* updateLastRoute?.threadId).is("42");
  });

  (deftest "does not pass threadId for regular DM without topic", async () => {
    const ctx = await buildCtx({
      message: {
        chat: { id: 1234, type: "private" },
      },
    });

    (expect* ctx).not.toBeNull();
    (expect* recordInboundSessionMock).toHaveBeenCalled();

    // Check that updateLastRoute does NOT include threadId
    const updateLastRoute = getUpdateLastRoute() as { threadId?: string; to?: string } | undefined;
    (expect* updateLastRoute).toBeDefined();
    (expect* updateLastRoute?.to).is("telegram:1234");
    (expect* updateLastRoute?.threadId).toBeUndefined();
  });

  (deftest "does not set updateLastRoute for group messages", async () => {
    const ctx = await buildCtx({
      message: {
        chat: { id: -1001234567890, type: "supergroup", title: "Test Group" },
        text: "@bot hello",
        message_thread_id: 99,
      },
      options: { forceWasMentioned: true },
      resolveGroupActivation: () => true,
    });

    (expect* ctx).not.toBeNull();
    (expect* recordInboundSessionMock).toHaveBeenCalled();

    // Check that updateLastRoute is undefined for groups
    (expect* getUpdateLastRoute()).toBeUndefined();
  });
});
