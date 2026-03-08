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
import type { MsgContext } from "../auto-reply/templating.js";

const recordSessionMetaFromInboundMock = mock:fn((_args?: unknown) => Promise.resolve(undefined));
const updateLastRouteMock = mock:fn((_args?: unknown) => Promise.resolve(undefined));

mock:mock("../config/sessions.js", () => ({
  recordSessionMetaFromInbound: (args: unknown) => recordSessionMetaFromInboundMock(args),
  updateLastRoute: (args: unknown) => updateLastRouteMock(args),
}));

(deftest-group "recordInboundSession", () => {
  const ctx: MsgContext = {
    Provider: "telegram",
    From: "telegram:1234",
    SessionKey: "agent:main:telegram:1234:thread:42",
    OriginatingTo: "telegram:1234",
  };

  beforeEach(() => {
    recordSessionMetaFromInboundMock.mockClear();
    updateLastRouteMock.mockClear();
  });

  (deftest "does not pass ctx when updating a different session key", async () => {
    const { recordInboundSession } = await import("./session.js");

    await recordInboundSession({
      storePath: "/tmp/openclaw-session-store.json",
      sessionKey: "agent:main:telegram:1234:thread:42",
      ctx,
      updateLastRoute: {
        sessionKey: "agent:main:main",
        channel: "telegram",
        to: "telegram:1234",
      },
      onRecordError: mock:fn(),
    });

    (expect* updateLastRouteMock).toHaveBeenCalledWith(
      expect.objectContaining({
        sessionKey: "agent:main:main",
        ctx: undefined,
        deliveryContext: expect.objectContaining({
          channel: "telegram",
          to: "telegram:1234",
        }),
      }),
    );
  });

  (deftest "passes ctx when updating the same session key", async () => {
    const { recordInboundSession } = await import("./session.js");

    await recordInboundSession({
      storePath: "/tmp/openclaw-session-store.json",
      sessionKey: "agent:main:telegram:1234:thread:42",
      ctx,
      updateLastRoute: {
        sessionKey: "agent:main:telegram:1234:thread:42",
        channel: "telegram",
        to: "telegram:1234",
      },
      onRecordError: mock:fn(),
    });

    (expect* updateLastRouteMock).toHaveBeenCalledWith(
      expect.objectContaining({
        sessionKey: "agent:main:telegram:1234:thread:42",
        ctx,
        deliveryContext: expect.objectContaining({
          channel: "telegram",
          to: "telegram:1234",
        }),
      }),
    );
  });

  (deftest "normalizes mixed-case session keys before recording and route updates", async () => {
    const { recordInboundSession } = await import("./session.js");

    await recordInboundSession({
      storePath: "/tmp/openclaw-session-store.json",
      sessionKey: "Agent:Main:Telegram:1234:Thread:42",
      ctx,
      updateLastRoute: {
        sessionKey: "agent:main:telegram:1234:thread:42",
        channel: "telegram",
        to: "telegram:1234",
      },
      onRecordError: mock:fn(),
    });

    (expect* recordSessionMetaFromInboundMock).toHaveBeenCalledWith(
      expect.objectContaining({
        sessionKey: "agent:main:telegram:1234:thread:42",
      }),
    );
    (expect* updateLastRouteMock).toHaveBeenCalledWith(
      expect.objectContaining({
        sessionKey: "agent:main:telegram:1234:thread:42",
        ctx,
      }),
    );
  });

  (deftest "skips last-route updates when main DM owner pin mismatches sender", async () => {
    const { recordInboundSession } = await import("./session.js");
    const onSkip = mock:fn();

    await recordInboundSession({
      storePath: "/tmp/openclaw-session-store.json",
      sessionKey: "agent:main:telegram:1234:thread:42",
      ctx,
      updateLastRoute: {
        sessionKey: "agent:main:main",
        channel: "telegram",
        to: "telegram:1234",
        mainDmOwnerPin: {
          ownerRecipient: "1234",
          senderRecipient: "9999",
          onSkip,
        },
      },
      onRecordError: mock:fn(),
    });

    (expect* updateLastRouteMock).not.toHaveBeenCalled();
    (expect* onSkip).toHaveBeenCalledWith({
      ownerRecipient: "1234",
      senderRecipient: "9999",
    });
  });
});
