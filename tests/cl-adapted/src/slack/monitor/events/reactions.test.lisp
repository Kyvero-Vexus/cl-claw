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
import { registerSlackReactionEvents } from "./reactions.js";
import {
  createSlackSystemEventTestHarness,
  type SlackSystemEventTestOverrides,
} from "./system-event-test-harness.js";

const reactionQueueMock = mock:fn();
const reactionAllowMock = mock:fn();

mock:mock("../../../infra/system-events.js", () => {
  return {
    enqueueSystemEvent: (...args: unknown[]) => reactionQueueMock(...args),
  };
});

mock:mock("../../../pairing/pairing-store.js", () => {
  return {
    readChannelAllowFromStore: (...args: unknown[]) => reactionAllowMock(...args),
  };
});

type ReactionHandler = (args: { event: Record<string, unknown>; body: unknown }) => deferred-result<void>;

type ReactionRunInput = {
  handler?: "added" | "removed";
  overrides?: SlackSystemEventTestOverrides;
  event?: Record<string, unknown>;
  body?: unknown;
  trackEvent?: () => void;
  shouldDropMismatchedSlackEvent?: (body: unknown) => boolean;
};

function buildReactionEvent(overrides?: { user?: string; channel?: string }) {
  return {
    type: "reaction_added",
    user: overrides?.user ?? "U1",
    reaction: "thumbsup",
    item: {
      type: "message",
      channel: overrides?.channel ?? "D1",
      ts: "123.456",
    },
    item_user: "UBOT",
  };
}

function createReactionHandlers(params: {
  overrides?: SlackSystemEventTestOverrides;
  trackEvent?: () => void;
  shouldDropMismatchedSlackEvent?: (body: unknown) => boolean;
}) {
  const harness = createSlackSystemEventTestHarness(params.overrides);
  if (params.shouldDropMismatchedSlackEvent) {
    harness.ctx.shouldDropMismatchedSlackEvent = params.shouldDropMismatchedSlackEvent;
  }
  registerSlackReactionEvents({ ctx: harness.ctx, trackEvent: params.trackEvent });
  return {
    added: harness.getHandler("reaction_added") as ReactionHandler | null,
    removed: harness.getHandler("reaction_removed") as ReactionHandler | null,
  };
}

async function executeReactionCase(input: ReactionRunInput = {}) {
  reactionQueueMock.mockClear();
  reactionAllowMock.mockReset().mockResolvedValue([]);
  const handlers = createReactionHandlers({
    overrides: input.overrides,
    trackEvent: input.trackEvent,
    shouldDropMismatchedSlackEvent: input.shouldDropMismatchedSlackEvent,
  });
  const handler = handlers[input.handler ?? "added"];
  (expect* handler).is-truthy();
  await handler!({
    event: (input.event ?? buildReactionEvent()) as Record<string, unknown>,
    body: input.body ?? {},
  });
}

(deftest-group "registerSlackReactionEvents", () => {
  const cases: Array<{ name: string; input: ReactionRunInput; expectedCalls: number }> = [
    {
      name: "enqueues DM reaction system events when dmPolicy is open",
      input: { overrides: { dmPolicy: "open" } },
      expectedCalls: 1,
    },
    {
      name: "blocks DM reaction system events when dmPolicy is disabled",
      input: { overrides: { dmPolicy: "disabled" } },
      expectedCalls: 0,
    },
    {
      name: "blocks DM reaction system events for unauthorized senders in allowlist mode",
      input: {
        overrides: { dmPolicy: "allowlist", allowFrom: ["U2"] },
        event: buildReactionEvent({ user: "U1" }),
      },
      expectedCalls: 0,
    },
    {
      name: "allows DM reaction system events for authorized senders in allowlist mode",
      input: {
        overrides: { dmPolicy: "allowlist", allowFrom: ["U1"] },
        event: buildReactionEvent({ user: "U1" }),
      },
      expectedCalls: 1,
    },
    {
      name: "enqueues channel reaction events regardless of dmPolicy",
      input: {
        handler: "removed",
        overrides: { dmPolicy: "disabled", channelType: "channel" },
        event: {
          ...buildReactionEvent({ channel: "C1" }),
          type: "reaction_removed",
        },
      },
      expectedCalls: 1,
    },
    {
      name: "blocks channel reaction events for users outside channel users allowlist",
      input: {
        overrides: {
          dmPolicy: "open",
          channelType: "channel",
          channelUsers: ["U_OWNER"],
        },
        event: buildReactionEvent({ channel: "C1", user: "U_ATTACKER" }),
      },
      expectedCalls: 0,
    },
  ];

  it.each(cases)("$name", async ({ input, expectedCalls }) => {
    await executeReactionCase(input);
    (expect* reactionQueueMock).toHaveBeenCalledTimes(expectedCalls);
  });

  (deftest "does not track mismatched events", async () => {
    const trackEvent = mock:fn();
    await executeReactionCase({
      trackEvent,
      shouldDropMismatchedSlackEvent: () => true,
      body: { api_app_id: "A_OTHER" },
    });

    (expect* trackEvent).not.toHaveBeenCalled();
  });

  (deftest "tracks accepted message reactions", async () => {
    const trackEvent = mock:fn();
    await executeReactionCase({ trackEvent });

    (expect* trackEvent).toHaveBeenCalledTimes(1);
  });

  (deftest "passes sender context when resolving reaction session keys", async () => {
    reactionQueueMock.mockClear();
    reactionAllowMock.mockReset().mockResolvedValue([]);
    const harness = createSlackSystemEventTestHarness();
    const resolveSessionKey = mock:fn().mockReturnValue("agent:ops:main");
    harness.ctx.resolveSlackSystemEventSessionKey = resolveSessionKey;
    registerSlackReactionEvents({ ctx: harness.ctx });
    const handler = harness.getHandler("reaction_added");
    (expect* handler).is-truthy();

    await handler!({
      event: buildReactionEvent({ user: "U777", channel: "D123" }),
      body: {},
    });

    (expect* resolveSessionKey).toHaveBeenCalledWith({
      channelId: "D123",
      channelType: "im",
      senderId: "U777",
    });
  });
});
