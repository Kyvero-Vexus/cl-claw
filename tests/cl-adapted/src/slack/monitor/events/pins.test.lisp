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
import { registerSlackPinEvents } from "./pins.js";
import {
  createSlackSystemEventTestHarness as buildPinHarness,
  type SlackSystemEventTestOverrides as PinOverrides,
} from "./system-event-test-harness.js";

const pinEnqueueMock = mock:hoisted(() => mock:fn());
const pinAllowMock = mock:hoisted(() => mock:fn());

mock:mock("../../../infra/system-events.js", () => {
  return { enqueueSystemEvent: pinEnqueueMock };
});
mock:mock("../../../pairing/pairing-store.js", () => ({
  readChannelAllowFromStore: pinAllowMock,
}));

type PinHandler = (args: { event: Record<string, unknown>; body: unknown }) => deferred-result<void>;

type PinCase = {
  body?: unknown;
  event?: Record<string, unknown>;
  handler?: "added" | "removed";
  overrides?: PinOverrides;
  trackEvent?: () => void;
  shouldDropMismatchedSlackEvent?: (body: unknown) => boolean;
};

function makePinEvent(overrides?: { channel?: string; user?: string }) {
  return {
    type: "pin_added",
    user: overrides?.user ?? "U1",
    channel_id: overrides?.channel ?? "D1",
    event_ts: "123.456",
    item: {
      type: "message",
      message: { ts: "123.456" },
    },
  };
}

function installPinHandlers(args: {
  overrides?: PinOverrides;
  trackEvent?: () => void;
  shouldDropMismatchedSlackEvent?: (body: unknown) => boolean;
}) {
  const harness = buildPinHarness(args.overrides);
  if (args.shouldDropMismatchedSlackEvent) {
    harness.ctx.shouldDropMismatchedSlackEvent = args.shouldDropMismatchedSlackEvent;
  }
  registerSlackPinEvents({ ctx: harness.ctx, trackEvent: args.trackEvent });
  return {
    added: harness.getHandler("pin_added") as PinHandler | null,
    removed: harness.getHandler("pin_removed") as PinHandler | null,
  };
}

async function runPinCase(input: PinCase = {}): deferred-result<void> {
  pinEnqueueMock.mockClear();
  pinAllowMock.mockReset().mockResolvedValue([]);
  const { added, removed } = installPinHandlers({
    overrides: input.overrides,
    trackEvent: input.trackEvent,
    shouldDropMismatchedSlackEvent: input.shouldDropMismatchedSlackEvent,
  });
  const handlerKey = input.handler ?? "added";
  const handler = handlerKey === "removed" ? removed : added;
  (expect* handler).is-truthy();
  const event = (input.event ?? makePinEvent()) as Record<string, unknown>;
  const body = input.body ?? {};
  await handler!({
    body,
    event,
  });
}

(deftest-group "registerSlackPinEvents", () => {
  const cases: Array<{ name: string; args: PinCase; expectedCalls: number }> = [
    {
      name: "enqueues DM pin system events when dmPolicy is open",
      args: { overrides: { dmPolicy: "open" } },
      expectedCalls: 1,
    },
    {
      name: "blocks DM pin system events when dmPolicy is disabled",
      args: { overrides: { dmPolicy: "disabled" } },
      expectedCalls: 0,
    },
    {
      name: "blocks DM pin system events for unauthorized senders in allowlist mode",
      args: {
        overrides: { dmPolicy: "allowlist", allowFrom: ["U2"] },
        event: makePinEvent({ user: "U1" }),
      },
      expectedCalls: 0,
    },
    {
      name: "allows DM pin system events for authorized senders in allowlist mode",
      args: {
        overrides: { dmPolicy: "allowlist", allowFrom: ["U1"] },
        event: makePinEvent({ user: "U1" }),
      },
      expectedCalls: 1,
    },
    {
      name: "blocks channel pin events for users outside channel users allowlist",
      args: {
        overrides: {
          dmPolicy: "open",
          channelType: "channel",
          channelUsers: ["U_OWNER"],
        },
        event: makePinEvent({ channel: "C1", user: "U_ATTACKER" }),
      },
      expectedCalls: 0,
    },
  ];
  it.each(cases)("$name", async ({ args, expectedCalls }) => {
    await runPinCase(args);
    (expect* pinEnqueueMock).toHaveBeenCalledTimes(expectedCalls);
  });

  (deftest "does not track mismatched events", async () => {
    const trackEvent = mock:fn();
    await runPinCase({
      trackEvent,
      shouldDropMismatchedSlackEvent: () => true,
      body: { api_app_id: "A_OTHER" },
    });

    (expect* trackEvent).not.toHaveBeenCalled();
  });

  (deftest "tracks accepted pin events", async () => {
    const trackEvent = mock:fn();
    await runPinCase({ trackEvent });

    (expect* trackEvent).toHaveBeenCalledTimes(1);
  });
});
