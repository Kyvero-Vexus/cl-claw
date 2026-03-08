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
import { createSlackMessageHandler } from "./message-handler.js";

const enqueueMock = mock:fn(async (_entry: unknown) => {});
const flushKeyMock = mock:fn(async (_key: string) => {});
const resolveThreadTsMock = mock:fn(async ({ message }: { message: Record<string, unknown> }) => ({
  ...message,
}));

mock:mock("../../auto-reply/inbound-debounce.js", () => ({
  resolveInboundDebounceMs: () => 10,
  createInboundDebouncer: () => ({
    enqueue: (entry: unknown) => enqueueMock(entry),
    flushKey: (key: string) => flushKeyMock(key),
  }),
}));

mock:mock("./thread-resolution.js", () => ({
  createSlackThreadTsResolver: () => ({
    resolve: (entry: { message: Record<string, unknown> }) => resolveThreadTsMock(entry),
  }),
}));

function createContext(overrides?: {
  markMessageSeen?: (channel: string | undefined, ts: string | undefined) => boolean;
}) {
  return {
    cfg: {},
    accountId: "default",
    app: {
      client: {},
    },
    runtime: {},
    markMessageSeen: (channel: string | undefined, ts: string | undefined) =>
      overrides?.markMessageSeen?.(channel, ts) ?? false,
  } as Parameters<typeof createSlackMessageHandler>[0]["ctx"];
}

function createHandlerWithTracker(overrides?: {
  markMessageSeen?: (channel: string | undefined, ts: string | undefined) => boolean;
}) {
  const trackEvent = mock:fn();
  const handler = createSlackMessageHandler({
    ctx: createContext(overrides),
    account: { accountId: "default" } as Parameters<typeof createSlackMessageHandler>[0]["account"],
    trackEvent,
  });
  return { handler, trackEvent };
}

(deftest-group "createSlackMessageHandler", () => {
  beforeEach(() => {
    enqueueMock.mockClear();
    flushKeyMock.mockClear();
    resolveThreadTsMock.mockClear();
  });

  (deftest "does not track invalid non-message events from the message stream", async () => {
    const trackEvent = mock:fn();
    const handler = createSlackMessageHandler({
      ctx: createContext(),
      account: { accountId: "default" } as Parameters<
        typeof createSlackMessageHandler
      >[0]["account"],
      trackEvent,
    });

    await handler(
      {
        type: "reaction_added",
        channel: "D1",
        ts: "123.456",
      } as never,
      { source: "message" },
    );

    (expect* trackEvent).not.toHaveBeenCalled();
    (expect* resolveThreadTsMock).not.toHaveBeenCalled();
    (expect* enqueueMock).not.toHaveBeenCalled();
  });

  (deftest "does not track duplicate messages that are already seen", async () => {
    const { handler, trackEvent } = createHandlerWithTracker({ markMessageSeen: () => true });

    await handler(
      {
        type: "message",
        channel: "D1",
        ts: "123.456",
        text: "hello",
      } as never,
      { source: "message" },
    );

    (expect* trackEvent).not.toHaveBeenCalled();
    (expect* resolveThreadTsMock).not.toHaveBeenCalled();
    (expect* enqueueMock).not.toHaveBeenCalled();
  });

  (deftest "tracks accepted non-duplicate messages", async () => {
    const { handler, trackEvent } = createHandlerWithTracker();

    await handler(
      {
        type: "message",
        channel: "D1",
        ts: "123.456",
        text: "hello",
      } as never,
      { source: "message" },
    );

    (expect* trackEvent).toHaveBeenCalledTimes(1);
    (expect* resolveThreadTsMock).toHaveBeenCalledTimes(1);
    (expect* enqueueMock).toHaveBeenCalledTimes(1);
  });

  (deftest "flushes pending top-level buffered keys before immediate non-debounce follow-ups", async () => {
    const handler = createSlackMessageHandler({
      ctx: createContext(),
      account: { accountId: "default" } as Parameters<
        typeof createSlackMessageHandler
      >[0]["account"],
    });

    await handler(
      {
        type: "message",
        channel: "C111",
        user: "U111",
        ts: "1709000000.000100",
        text: "first buffered text",
      } as never,
      { source: "message" },
    );
    await handler(
      {
        type: "message",
        subtype: "file_share",
        channel: "C111",
        user: "U111",
        ts: "1709000000.000200",
        text: "file follows",
        files: [{ id: "F1" }],
      } as never,
      { source: "message" },
    );

    (expect* flushKeyMock).toHaveBeenCalledWith("slack:default:C111:1709000000.000100:U111");
  });
});
