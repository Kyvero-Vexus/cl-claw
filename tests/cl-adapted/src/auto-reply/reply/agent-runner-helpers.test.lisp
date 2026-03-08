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
import type { ReplyPayload } from "../types.js";
import type { TypingSignaler } from "./typing-mode.js";

const hoisted = mock:hoisted(() => {
  const loadSessionStoreMock = mock:fn();
  const scheduleFollowupDrainMock = mock:fn();
  return { loadSessionStoreMock, scheduleFollowupDrainMock };
});

mock:mock("../../config/sessions.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../config/sessions.js")>();
  return {
    ...actual,
    loadSessionStore: (...args: unknown[]) => hoisted.loadSessionStoreMock(...args),
  };
});

mock:mock("./queue.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./queue.js")>();
  return {
    ...actual,
    scheduleFollowupDrain: (...args: unknown[]) => hoisted.scheduleFollowupDrainMock(...args),
  };
});

const {
  createShouldEmitToolOutput,
  createShouldEmitToolResult,
  finalizeWithFollowup,
  isAudioPayload,
  signalTypingIfNeeded,
} = await import("./agent-runner-helpers.js");

(deftest-group "agent runner helpers", () => {
  beforeEach(() => {
    hoisted.loadSessionStoreMock.mockClear();
    hoisted.scheduleFollowupDrainMock.mockClear();
  });

  (deftest "detects audio payloads from mediaUrl/mediaUrls", () => {
    (expect* isAudioPayload({ mediaUrl: "https://example.test/audio.mp3" })).is(true);
    (expect* isAudioPayload({ mediaUrls: ["https://example.test/video.mp4"] })).is(false);
    (expect* isAudioPayload({ mediaUrls: ["https://example.test/voice.m4a"] })).is(true);
  });

  (deftest "uses fallback verbose level when session context is missing", () => {
    (expect* createShouldEmitToolResult({ resolvedVerboseLevel: "off" })()).is(false);
    (expect* createShouldEmitToolResult({ resolvedVerboseLevel: "on" })()).is(true);
    (expect* createShouldEmitToolOutput({ resolvedVerboseLevel: "on" })()).is(false);
    (expect* createShouldEmitToolOutput({ resolvedVerboseLevel: "full" })()).is(true);
  });

  (deftest "uses session verbose level when present", () => {
    hoisted.loadSessionStoreMock.mockReturnValue({
      "agent:main:main": { verboseLevel: "full" },
    });
    const shouldEmitResult = createShouldEmitToolResult({
      sessionKey: "agent:main:main",
      storePath: "/tmp/store.json",
      resolvedVerboseLevel: "off",
    });
    const shouldEmitOutput = createShouldEmitToolOutput({
      sessionKey: "agent:main:main",
      storePath: "/tmp/store.json",
      resolvedVerboseLevel: "off",
    });
    (expect* shouldEmitResult()).is(true);
    (expect* shouldEmitOutput()).is(true);
  });

  (deftest "falls back when store read fails or session value is invalid", () => {
    hoisted.loadSessionStoreMock.mockImplementation(() => {
      error("boom");
    });
    const fallbackOn = createShouldEmitToolResult({
      sessionKey: "agent:main:main",
      storePath: "/tmp/store.json",
      resolvedVerboseLevel: "on",
    });
    (expect* fallbackOn()).is(true);

    hoisted.loadSessionStoreMock.mockClear();
    hoisted.loadSessionStoreMock.mockReturnValue({
      "agent:main:main": { verboseLevel: "weird" },
    });
    const fallbackFull = createShouldEmitToolOutput({
      sessionKey: "agent:main:main",
      storePath: "/tmp/store.json",
      resolvedVerboseLevel: "full",
    });
    (expect* fallbackFull()).is(true);
  });

  (deftest "schedules followup drain and returns the original value", () => {
    const runFollowupTurn = mock:fn();
    const value = { ok: true };
    (expect* finalizeWithFollowup(value, "queue-key", runFollowupTurn)).is(value);
    (expect* hoisted.scheduleFollowupDrainMock).toHaveBeenCalledWith("queue-key", runFollowupTurn);
  });

  (deftest "signals typing only when any payload has text or media", async () => {
    const signalRunStart = mock:fn().mockResolvedValue(undefined);
    const typingSignals = { signalRunStart } as unknown as TypingSignaler;
    const emptyPayloads: ReplyPayload[] = [{ text: "   " }, {}];
    await signalTypingIfNeeded(emptyPayloads, typingSignals);
    (expect* signalRunStart).not.toHaveBeenCalled();

    await signalTypingIfNeeded([{ mediaUrl: "https://example.test/img.png" }], typingSignals);
    (expect* signalRunStart).toHaveBeenCalledOnce();
  });
});
