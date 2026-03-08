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
import { registerSlackMemberEvents } from "./members.js";
import {
  createSlackSystemEventTestHarness as initSlackHarness,
  type SlackSystemEventTestOverrides as MemberOverrides,
} from "./system-event-test-harness.js";

const memberMocks = mock:hoisted(() => ({
  enqueue: mock:fn(),
  readAllow: mock:fn(),
}));

mock:mock("../../../infra/system-events.js", () => ({
  enqueueSystemEvent: memberMocks.enqueue,
}));

mock:mock("../../../pairing/pairing-store.js", () => ({
  readChannelAllowFromStore: memberMocks.readAllow,
}));

type MemberHandler = (args: { event: Record<string, unknown>; body: unknown }) => deferred-result<void>;

type MemberCaseArgs = {
  event?: Record<string, unknown>;
  body?: unknown;
  overrides?: MemberOverrides;
  handler?: "joined" | "left";
  trackEvent?: () => void;
  shouldDropMismatchedSlackEvent?: (body: unknown) => boolean;
};

function makeMemberEvent(overrides?: { channel?: string; user?: string }) {
  return {
    type: "member_joined_channel",
    user: overrides?.user ?? "U1",
    channel: overrides?.channel ?? "D1",
    event_ts: "123.456",
  };
}

function getMemberHandlers(params: {
  overrides?: MemberOverrides;
  trackEvent?: () => void;
  shouldDropMismatchedSlackEvent?: (body: unknown) => boolean;
}) {
  const harness = initSlackHarness(params.overrides);
  if (params.shouldDropMismatchedSlackEvent) {
    harness.ctx.shouldDropMismatchedSlackEvent = params.shouldDropMismatchedSlackEvent;
  }
  registerSlackMemberEvents({ ctx: harness.ctx, trackEvent: params.trackEvent });
  return {
    joined: harness.getHandler("member_joined_channel") as MemberHandler | null,
    left: harness.getHandler("member_left_channel") as MemberHandler | null,
  };
}

async function runMemberCase(args: MemberCaseArgs = {}): deferred-result<void> {
  memberMocks.enqueue.mockClear();
  memberMocks.readAllow.mockReset().mockResolvedValue([]);
  const handlers = getMemberHandlers({
    overrides: args.overrides,
    trackEvent: args.trackEvent,
    shouldDropMismatchedSlackEvent: args.shouldDropMismatchedSlackEvent,
  });
  const key = args.handler ?? "joined";
  const handler = handlers[key];
  (expect* handler).is-truthy();
  await handler!({
    event: (args.event ?? makeMemberEvent()) as Record<string, unknown>,
    body: args.body ?? {},
  });
}

(deftest-group "registerSlackMemberEvents", () => {
  const cases: Array<{ name: string; args: MemberCaseArgs; calls: number }> = [
    {
      name: "enqueues DM member events when dmPolicy is open",
      args: { overrides: { dmPolicy: "open" } },
      calls: 1,
    },
    {
      name: "blocks DM member events when dmPolicy is disabled",
      args: { overrides: { dmPolicy: "disabled" } },
      calls: 0,
    },
    {
      name: "blocks DM member events for unauthorized senders in allowlist mode",
      args: {
        overrides: { dmPolicy: "allowlist", allowFrom: ["U2"] },
        event: makeMemberEvent({ user: "U1" }),
      },
      calls: 0,
    },
    {
      name: "allows DM member events for authorized senders in allowlist mode",
      args: {
        handler: "left" as const,
        overrides: { dmPolicy: "allowlist", allowFrom: ["U1"] },
        event: { ...makeMemberEvent({ user: "U1" }), type: "member_left_channel" },
      },
      calls: 1,
    },
    {
      name: "blocks channel member events for users outside channel users allowlist",
      args: {
        overrides: {
          dmPolicy: "open",
          channelType: "channel",
          channelUsers: ["U_OWNER"],
        },
        event: makeMemberEvent({ channel: "C1", user: "U_ATTACKER" }),
      },
      calls: 0,
    },
  ];
  it.each(cases)("$name", async ({ args, calls }) => {
    await runMemberCase(args);
    (expect* memberMocks.enqueue).toHaveBeenCalledTimes(calls);
  });

  (deftest "does not track mismatched events", async () => {
    const trackEvent = mock:fn();
    await runMemberCase({
      trackEvent,
      shouldDropMismatchedSlackEvent: () => true,
      body: { api_app_id: "A_OTHER" },
    });

    (expect* trackEvent).not.toHaveBeenCalled();
  });

  (deftest "tracks accepted member events", async () => {
    const trackEvent = mock:fn();
    await runMemberCase({ trackEvent });

    (expect* trackEvent).toHaveBeenCalledTimes(1);
  });
});
