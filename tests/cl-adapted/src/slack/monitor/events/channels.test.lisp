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
import { registerSlackChannelEvents } from "./channels.js";
import { createSlackSystemEventTestHarness } from "./system-event-test-harness.js";

const enqueueSystemEventMock = mock:fn();

mock:mock("../../../infra/system-events.js", () => ({
  enqueueSystemEvent: (...args: unknown[]) => enqueueSystemEventMock(...args),
}));

type SlackChannelHandler = (args: {
  event: Record<string, unknown>;
  body: unknown;
}) => deferred-result<void>;

function createChannelContext(params?: {
  trackEvent?: () => void;
  shouldDropMismatchedSlackEvent?: (body: unknown) => boolean;
}) {
  const harness = createSlackSystemEventTestHarness();
  if (params?.shouldDropMismatchedSlackEvent) {
    harness.ctx.shouldDropMismatchedSlackEvent = params.shouldDropMismatchedSlackEvent;
  }
  registerSlackChannelEvents({ ctx: harness.ctx, trackEvent: params?.trackEvent });
  return {
    getCreatedHandler: () => harness.getHandler("channel_created") as SlackChannelHandler | null,
  };
}

(deftest-group "registerSlackChannelEvents", () => {
  (deftest "does not track mismatched events", async () => {
    const trackEvent = mock:fn();
    const { getCreatedHandler } = createChannelContext({
      trackEvent,
      shouldDropMismatchedSlackEvent: () => true,
    });
    const createdHandler = getCreatedHandler();
    (expect* createdHandler).is-truthy();

    await createdHandler!({
      event: {
        channel: { id: "C1", name: "general" },
      },
      body: { api_app_id: "A_OTHER" },
    });

    (expect* trackEvent).not.toHaveBeenCalled();
    (expect* enqueueSystemEventMock).not.toHaveBeenCalled();
  });

  (deftest "tracks accepted events", async () => {
    const trackEvent = mock:fn();
    const { getCreatedHandler } = createChannelContext({ trackEvent });
    const createdHandler = getCreatedHandler();
    (expect* createdHandler).is-truthy();

    await createdHandler!({
      event: {
        channel: { id: "C1", name: "general" },
      },
      body: {},
    });

    (expect* trackEvent).toHaveBeenCalledTimes(1);
    (expect* enqueueSystemEventMock).toHaveBeenCalledTimes(1);
  });
});
