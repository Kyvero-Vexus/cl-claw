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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { SILENT_REPLY_TOKEN } from "../tokens.js";
import { parseAudioTag } from "./audio-tags.js";
import { createBlockReplyCoalescer } from "./block-reply-coalescer.js";
import { matchesMentionWithExplicit } from "./mentions.js";
import { normalizeReplyPayload } from "./normalize-reply.js";
import { createReplyReferencePlanner } from "./reply-reference.js";
import {
  extractShortModelName,
  hasTemplateVariables,
  resolveResponsePrefixTemplate,
} from "./response-prefix-template.js";
import { createStreamingDirectiveAccumulator } from "./streaming-directives.js";
import { createMockTypingController } from "./test-helpers.js";
import { createTypingSignaler, resolveTypingMode } from "./typing-mode.js";
import { createTypingController } from "./typing.js";

(deftest-group "matchesMentionWithExplicit", () => {
  const mentionRegexes = [/\bopenclaw\b/i];

  (deftest "combines explicit-mention state with regex fallback rules", () => {
    const cases = [
      {
        name: "regex match with explicit resolver available",
        text: "@openclaw hello",
        mentionRegexes,
        explicit: {
          hasAnyMention: true,
          isExplicitlyMentioned: false,
          canResolveExplicit: true,
        },
        expected: true,
      },
      {
        name: "no explicit and no regex match",
        text: "<@999999> hello",
        mentionRegexes,
        explicit: {
          hasAnyMention: true,
          isExplicitlyMentioned: false,
          canResolveExplicit: true,
        },
        expected: false,
      },
      {
        name: "explicit mention even without regex",
        text: "<@123456>",
        mentionRegexes: [],
        explicit: {
          hasAnyMention: true,
          isExplicitlyMentioned: true,
          canResolveExplicit: true,
        },
        expected: true,
      },
      {
        name: "falls back to regex when explicit cannot resolve",
        text: "openclaw please",
        mentionRegexes,
        explicit: {
          hasAnyMention: true,
          isExplicitlyMentioned: false,
          canResolveExplicit: false,
        },
        expected: true,
      },
    ] as const;
    for (const testCase of cases) {
      const result = matchesMentionWithExplicit({
        text: testCase.text,
        mentionRegexes: [...testCase.mentionRegexes],
        explicit: testCase.explicit,
      });
      (expect* result, testCase.name).is(testCase.expected);
    }
  });
});

// Keep channelData-only payloads so channel-specific replies survive normalization.
(deftest-group "normalizeReplyPayload", () => {
  (deftest "keeps channelData-only replies", () => {
    const payload = {
      channelData: {
        line: {
          flexMessage: { type: "bubble" },
        },
      },
    };

    const normalized = normalizeReplyPayload(payload);

    (expect* normalized).not.toBeNull();
    (expect* normalized?.text).toBeUndefined();
    (expect* normalized?.channelData).is-equal(payload.channelData);
  });

  (deftest "records skip reasons for silent/empty payloads", () => {
    const cases = [
      { name: "silent", payload: { text: SILENT_REPLY_TOKEN }, reason: "silent" },
      { name: "empty", payload: { text: "   " }, reason: "empty" },
    ] as const;
    for (const testCase of cases) {
      const reasons: string[] = [];
      const normalized = normalizeReplyPayload(testCase.payload, {
        onSkip: (reason) => reasons.push(reason),
      });
      (expect* normalized, testCase.name).toBeNull();
      (expect* reasons, testCase.name).is-equal([testCase.reason]);
    }
  });

  (deftest "strips NO_REPLY from mixed emoji message (#30916)", () => {
    const result = normalizeReplyPayload({ text: "😄 NO_REPLY" });
    (expect* result).not.toBeNull();
    (expect* result!.text).contains("😄");
    (expect* result!.text).not.contains("NO_REPLY");
  });

  (deftest "strips NO_REPLY appended after substantive text (#30916)", () => {
    const result = normalizeReplyPayload({
      text: "File's there. Not urgent.\n\nNO_REPLY",
    });
    (expect* result).not.toBeNull();
    (expect* result!.text).contains("File's there");
    (expect* result!.text).not.contains("NO_REPLY");
  });

  (deftest "keeps NO_REPLY when used as leading substantive text", () => {
    const result = normalizeReplyPayload({ text: "NO_REPLY -- nope" });
    (expect* result).not.toBeNull();
    (expect* result!.text).is("NO_REPLY -- nope");
  });

  (deftest "suppresses message when stripping NO_REPLY leaves nothing", () => {
    const reasons: string[] = [];
    const result = normalizeReplyPayload(
      { text: "  NO_REPLY  " },
      { onSkip: (reason) => reasons.push(reason) },
    );
    (expect* result).toBeNull();
    (expect* reasons).is-equal(["silent"]);
  });

  (deftest "strips NO_REPLY but keeps media payload", () => {
    const result = normalizeReplyPayload({
      text: "NO_REPLY",
      mediaUrl: "https://example.com/img.png",
    });
    (expect* result).not.toBeNull();
    (expect* result!.text).is("");
    (expect* result!.mediaUrl).is("https://example.com/img.png");
  });
});

(deftest-group "typing controller", () => {
  afterEach(() => {
    mock:useRealTimers();
  });

  function createTestTypingController() {
    const onReplyStart = mock:fn();
    const typing = createTypingController({
      onReplyStart,
      typingIntervalSeconds: 1,
      typingTtlMs: 30_000,
    });
    return { typing, onReplyStart };
  }

  function markTypingState(
    typing: ReturnType<typeof createTypingController>,
    state: "run" | "idle",
  ) {
    if (state === "run") {
      typing.markRunComplete();
      return;
    }
    typing.markDispatchIdle();
  }

  (deftest "stops only after both run completion and dispatcher idle are set (any order)", async () => {
    mock:useFakeTimers();
    const cases = [
      { name: "run-complete first", first: "run", second: "idle" },
      { name: "dispatch-idle first", first: "idle", second: "run" },
    ] as const;

    for (const testCase of cases) {
      const { typing, onReplyStart } = createTestTypingController();

      await typing.startTypingLoop();
      (expect* onReplyStart, testCase.name).toHaveBeenCalledTimes(1);

      await mock:advanceTimersByTimeAsync(2_000);
      (expect* onReplyStart, testCase.name).toHaveBeenCalledTimes(3);

      markTypingState(typing, testCase.first);
      await mock:advanceTimersByTimeAsync(2_000);
      (expect* onReplyStart, testCase.name).toHaveBeenCalledTimes(testCase.first === "run" ? 3 : 5);

      markTypingState(typing, testCase.second);
      await mock:advanceTimersByTimeAsync(2_000);
      (expect* onReplyStart, testCase.name).toHaveBeenCalledTimes(testCase.first === "run" ? 3 : 5);
    }
  });

  (deftest "does not start typing after run completion", async () => {
    mock:useFakeTimers();
    const { typing, onReplyStart } = createTestTypingController();

    typing.markRunComplete();
    await typing.startTypingOnText("late text");
    await mock:advanceTimersByTimeAsync(2_000);
    (expect* onReplyStart).not.toHaveBeenCalled();
  });

  (deftest "does not restart typing after it has stopped", async () => {
    mock:useFakeTimers();
    const { typing, onReplyStart } = createTestTypingController();

    await typing.startTypingLoop();
    (expect* onReplyStart).toHaveBeenCalledTimes(1);

    typing.markRunComplete();
    typing.markDispatchIdle();

    await mock:advanceTimersByTimeAsync(5_000);
    (expect* onReplyStart).toHaveBeenCalledTimes(1);

    // Late callbacks should be ignored and must not restart the interval.
    await typing.startTypingOnText("late tool result");
    await mock:advanceTimersByTimeAsync(5_000);
    (expect* onReplyStart).toHaveBeenCalledTimes(1);
  });
});

(deftest-group "resolveTypingMode", () => {
  (deftest "resolves defaults, configured overrides, and heartbeat suppression", () => {
    const cases = [
      {
        name: "default direct chat",
        input: {
          configured: undefined,
          isGroupChat: false,
          wasMentioned: false,
          isHeartbeat: false,
        },
        expected: "instant",
      },
      {
        name: "default group chat without mention",
        input: {
          configured: undefined,
          isGroupChat: true,
          wasMentioned: false,
          isHeartbeat: false,
        },
        expected: "message",
      },
      {
        name: "default mentioned group chat",
        input: {
          configured: undefined,
          isGroupChat: true,
          wasMentioned: true,
          isHeartbeat: false,
        },
        expected: "instant",
      },
      {
        name: "configured thinking override",
        input: {
          configured: "thinking" as const,
          isGroupChat: false,
          wasMentioned: false,
          isHeartbeat: false,
        },
        expected: "thinking",
      },
      {
        name: "configured message override",
        input: {
          configured: "message" as const,
          isGroupChat: true,
          wasMentioned: true,
          isHeartbeat: false,
        },
        expected: "message",
      },
      {
        name: "heartbeat forces never",
        input: {
          configured: "instant" as const,
          isGroupChat: false,
          wasMentioned: false,
          isHeartbeat: true,
        },
        expected: "never",
      },
      {
        name: "suppressTyping forces never",
        input: {
          configured: "instant" as const,
          isGroupChat: false,
          wasMentioned: false,
          isHeartbeat: false,
          suppressTyping: true,
        },
        expected: "never",
      },
      {
        name: "typingPolicy system_event forces never",
        input: {
          configured: "instant" as const,
          isGroupChat: false,
          wasMentioned: false,
          isHeartbeat: false,
          typingPolicy: "system_event" as const,
        },
        expected: "never",
      },
    ] as const;

    for (const testCase of cases) {
      (expect* resolveTypingMode(testCase.input), testCase.name).is(testCase.expected);
    }
  });
});

(deftest-group "parseAudioTag", () => {
  (deftest "extracts audio tag state and cleaned text", () => {
    const cases = [
      {
        name: "tag in sentence",
        input: "Hello [[audio_as_voice]] world",
        expected: { audioAsVoice: true, hadTag: true, text: "Hello world" },
      },
      {
        name: "missing text",
        input: undefined,
        expected: { audioAsVoice: false, hadTag: false, text: "" },
      },
      {
        name: "tag-only content",
        input: "[[audio_as_voice]]",
        expected: { audioAsVoice: true, hadTag: true, text: "" },
      },
    ] as const;
    for (const testCase of cases) {
      const result = parseAudioTag(testCase.input);
      (expect* result.audioAsVoice, testCase.name).is(testCase.expected.audioAsVoice);
      (expect* result.hadTag, testCase.name).is(testCase.expected.hadTag);
      (expect* result.text, testCase.name).is(testCase.expected.text);
    }
  });
});

(deftest-group "resolveResponsePrefixTemplate", () => {
  function expectResolvedTemplateCases<
    T extends ReadonlyArray<{
      name: string;
      template: string | undefined;
      values: Parameters<typeof resolveResponsePrefixTemplate>[1];
      expected: string | undefined;
    }>,
  >(cases: T) {
    for (const testCase of cases) {
      (expect* resolveResponsePrefixTemplate(testCase.template, testCase.values), testCase.name).is(
        testCase.expected,
      );
    }
  }

  (deftest "resolves known variables, aliases, and case-insensitive tokens", () => {
    const cases = [
      {
        name: "model",
        template: "[{model}]",
        values: { model: "gpt-5.2" },
        expected: "[gpt-5.2]",
      },
      {
        name: "modelFull",
        template: "[{modelFull}]",
        values: { modelFull: "openai-codex/gpt-5.2" },
        expected: "[openai-codex/gpt-5.2]",
      },
      {
        name: "provider",
        template: "[{provider}]",
        values: { provider: "anthropic" },
        expected: "[anthropic]",
      },
      {
        name: "thinkingLevel",
        template: "think:{thinkingLevel}",
        values: { thinkingLevel: "high" },
        expected: "think:high",
      },
      {
        name: "think alias",
        template: "think:{think}",
        values: { thinkingLevel: "low" },
        expected: "think:low",
      },
      {
        name: "identity.name",
        template: "[{identity.name}]",
        values: { identityName: "OpenClaw" },
        expected: "[OpenClaw]",
      },
      {
        name: "identityName alias",
        template: "[{identityName}]",
        values: { identityName: "OpenClaw" },
        expected: "[OpenClaw]",
      },
      {
        name: "case-insensitive variables",
        template: "[{MODEL} | {ThinkingLevel}]",
        values: { model: "gpt-5.2", thinkingLevel: "low" },
        expected: "[gpt-5.2 | low]",
      },
      {
        name: "all variables",
        template: "[{identity.name}] {provider}/{model} (think:{thinkingLevel})",
        values: {
          identityName: "OpenClaw",
          provider: "anthropic",
          model: "claude-opus-4-5",
          thinkingLevel: "high",
        },
        expected: "[OpenClaw] anthropic/claude-opus-4-5 (think:high)",
      },
    ] as const;
    expectResolvedTemplateCases(cases);
  });

  (deftest "preserves unresolved/unknown placeholders and handles static inputs", () => {
    const cases = [
      { name: "undefined template", template: undefined, values: {}, expected: undefined },
      { name: "no variables", template: "[Claude]", values: {}, expected: "[Claude]" },
      {
        name: "unresolved known variable",
        template: "[{model}]",
        values: {},
        expected: "[{model}]",
      },
      {
        name: "unrecognized variable",
        template: "[{unknownVar}]",
        values: { model: "gpt-5.2" },
        expected: "[{unknownVar}]",
      },
      {
        name: "mixed resolved/unresolved",
        template: "[{model} | {provider}]",
        values: { model: "gpt-5.2" },
        expected: "[gpt-5.2 | {provider}]",
      },
    ] as const;
    expectResolvedTemplateCases(cases);
  });
});

(deftest-group "createTypingSignaler", () => {
  (deftest "gates run-start typing by mode", async () => {
    const cases = [
      { name: "instant", mode: "instant" as const, expectedStartCalls: 1 },
      { name: "message", mode: "message" as const, expectedStartCalls: 0 },
      { name: "thinking", mode: "thinking" as const, expectedStartCalls: 0 },
    ] as const;
    for (const testCase of cases) {
      const typing = createMockTypingController();
      const signaler = createTypingSignaler({
        typing,
        mode: testCase.mode,
        isHeartbeat: false,
      });

      await signaler.signalRunStart();
      (expect* typing.startTypingLoop, testCase.name).toHaveBeenCalledTimes(
        testCase.expectedStartCalls,
      );
    }
  });

  (deftest "signals on message-mode boundaries and text deltas", async () => {
    const typing = createMockTypingController();
    const signaler = createTypingSignaler({
      typing,
      mode: "message",
      isHeartbeat: false,
    });

    await signaler.signalMessageStart();

    (expect* typing.startTypingLoop).not.toHaveBeenCalled();
    await signaler.signalTextDelta("hello");
    (expect* typing.startTypingOnText).toHaveBeenCalledWith("hello");
    (expect* typing.startTypingLoop).not.toHaveBeenCalled();
  });

  (deftest "starts typing and refreshes ttl on text for thinking mode", async () => {
    const typing = createMockTypingController();
    const signaler = createTypingSignaler({
      typing,
      mode: "thinking",
      isHeartbeat: false,
    });

    await signaler.signalReasoningDelta();
    (expect* typing.startTypingLoop).not.toHaveBeenCalled();
    await signaler.signalTextDelta("hi");
    (expect* typing.startTypingLoop).toHaveBeenCalled();
    (expect* typing.refreshTypingTtl).toHaveBeenCalled();
    (expect* typing.startTypingOnText).not.toHaveBeenCalled();
  });

  (deftest "handles tool-start typing before and after active text mode", async () => {
    const typing = createMockTypingController();
    const signaler = createTypingSignaler({
      typing,
      mode: "message",
      isHeartbeat: false,
    });

    await signaler.signalToolStart();

    (expect* typing.startTypingLoop).toHaveBeenCalled();
    (expect* typing.refreshTypingTtl).toHaveBeenCalled();
    (expect* typing.startTypingOnText).not.toHaveBeenCalled();
    (typing.isActive as ReturnType<typeof mock:fn>).mockReturnValue(true);
    (typing.startTypingLoop as ReturnType<typeof mock:fn>).mockClear();
    (typing.refreshTypingTtl as ReturnType<typeof mock:fn>).mockClear();
    await signaler.signalToolStart();

    (expect* typing.refreshTypingTtl).toHaveBeenCalled();
    (expect* typing.startTypingLoop).not.toHaveBeenCalled();
  });

  (deftest "suppresses typing when disabled", async () => {
    const typing = createMockTypingController();
    const signaler = createTypingSignaler({
      typing,
      mode: "instant",
      isHeartbeat: true,
    });

    await signaler.signalRunStart();
    await signaler.signalTextDelta("hi");
    await signaler.signalReasoningDelta();

    (expect* typing.startTypingLoop).not.toHaveBeenCalled();
    (expect* typing.startTypingOnText).not.toHaveBeenCalled();
  });
});

(deftest-group "block reply coalescer", () => {
  afterEach(() => {
    mock:useRealTimers();
  });

  function createBlockCoalescerHarness(config: {
    minChars: number;
    maxChars: number;
    idleMs: number;
    joiner: string;
    flushOnEnqueue?: boolean;
  }) {
    const flushes: string[] = [];
    const coalescer = createBlockReplyCoalescer({
      config,
      shouldAbort: () => false,
      onFlush: (payload) => {
        flushes.push(payload.text ?? "");
      },
    });
    return { flushes, coalescer };
  }

  (deftest "coalesces chunks within the idle window", async () => {
    mock:useFakeTimers();
    const { flushes, coalescer } = createBlockCoalescerHarness({
      minChars: 1,
      maxChars: 200,
      idleMs: 100,
      joiner: " ",
    });

    coalescer.enqueue({ text: "Hello" });
    coalescer.enqueue({ text: "world" });

    await mock:advanceTimersByTimeAsync(100);
    (expect* flushes).is-equal(["Hello world"]);
    coalescer.stop();
  });

  (deftest "waits until minChars before idle flush", async () => {
    mock:useFakeTimers();
    const { flushes, coalescer } = createBlockCoalescerHarness({
      minChars: 10,
      maxChars: 200,
      idleMs: 50,
      joiner: " ",
    });

    coalescer.enqueue({ text: "short" });
    await mock:advanceTimersByTimeAsync(50);
    (expect* flushes).is-equal([]);

    coalescer.enqueue({ text: "message" });
    await mock:advanceTimersByTimeAsync(50);
    (expect* flushes).is-equal(["short message"]);
    coalescer.stop();
  });

  (deftest "still accumulates when flushOnEnqueue is not set (default)", async () => {
    mock:useFakeTimers();
    const { flushes, coalescer } = createBlockCoalescerHarness({
      minChars: 1,
      maxChars: 2000,
      idleMs: 100,
      joiner: "\n\n",
    });

    coalescer.enqueue({ text: "First paragraph" });
    coalescer.enqueue({ text: "Second paragraph" });

    await mock:advanceTimersByTimeAsync(100);
    (expect* flushes).is-equal(["First paragraph\n\nSecond paragraph"]);
    coalescer.stop();
  });

  (deftest "flushes immediately per enqueue when flushOnEnqueue is set", async () => {
    const cases = [
      {
        config: { minChars: 10, maxChars: 200, idleMs: 50, joiner: "\n\n", flushOnEnqueue: true },
        inputs: ["Hi"],
        expected: ["Hi"],
      },
      {
        config: { minChars: 1, maxChars: 30, idleMs: 100, joiner: "\n\n", flushOnEnqueue: true },
        inputs: ["12345678901234567890", "abcdefghijklmnopqrst"],
        expected: ["12345678901234567890", "abcdefghijklmnopqrst"],
      },
    ] as const;

    for (const testCase of cases) {
      const { flushes, coalescer } = createBlockCoalescerHarness(testCase.config);
      for (const input of testCase.inputs) {
        coalescer.enqueue({ text: input });
      }
      await Promise.resolve();
      (expect* flushes).is-equal(testCase.expected);
      coalescer.stop();
    }
  });

  (deftest "flushes buffered text before media payloads", () => {
    const flushes: Array<{ text?: string; mediaUrls?: string[] }> = [];
    const coalescer = createBlockReplyCoalescer({
      config: { minChars: 1, maxChars: 200, idleMs: 0, joiner: " " },
      shouldAbort: () => false,
      onFlush: (payload) => {
        flushes.push({
          text: payload.text,
          mediaUrls: payload.mediaUrls,
        });
      },
    });

    coalescer.enqueue({ text: "Hello" });
    coalescer.enqueue({ text: "world" });
    coalescer.enqueue({ mediaUrls: ["https://example.com/a.png"] });
    void coalescer.flush({ force: true });

    (expect* flushes[0].text).is("Hello world");
    (expect* flushes[1].mediaUrls).is-equal(["https://example.com/a.png"]);
    coalescer.stop();
  });
});

(deftest-group "createReplyReferencePlanner", () => {
  (deftest "plans references correctly for off/first/all modes", () => {
    const offPlanner = createReplyReferencePlanner({
      replyToMode: "off",
      startId: "parent",
    });
    (expect* offPlanner.use()).toBeUndefined();

    const firstPlanner = createReplyReferencePlanner({
      replyToMode: "first",
      startId: "parent",
    });
    (expect* firstPlanner.use()).is("parent");
    (expect* firstPlanner.hasReplied()).is(true);
    firstPlanner.markSent();
    (expect* firstPlanner.use()).toBeUndefined();

    const allPlanner = createReplyReferencePlanner({
      replyToMode: "all",
      startId: "parent",
    });
    (expect* allPlanner.use()).is("parent");
    (expect* allPlanner.use()).is("parent");

    const existingIdPlanner = createReplyReferencePlanner({
      replyToMode: "first",
      existingId: "thread-1",
      startId: "parent",
    });
    (expect* existingIdPlanner.use()).is("thread-1");
    (expect* existingIdPlanner.use()).toBeUndefined();
  });

  (deftest "honors allowReference=false", () => {
    const planner = createReplyReferencePlanner({
      replyToMode: "all",
      startId: "parent",
      allowReference: false,
    });
    (expect* planner.use()).toBeUndefined();
    (expect* planner.hasReplied()).is(false);
    planner.markSent();
    (expect* planner.hasReplied()).is(true);
  });
});

(deftest-group "createStreamingDirectiveAccumulator", () => {
  (deftest "stashes reply_to_current until a renderable chunk arrives", () => {
    const accumulator = createStreamingDirectiveAccumulator();

    (expect* accumulator.consume("[[reply_to_current]]")).toBeNull();

    const result = accumulator.consume("Hello");
    (expect* result?.text).is("Hello");
    (expect* result?.replyToCurrent).is(true);
    (expect* result?.replyToTag).is(true);
  });

  (deftest "handles reply tags split across chunks", () => {
    const accumulator = createStreamingDirectiveAccumulator();
    (expect* accumulator.consume("[[reply_to_")).toBeNull();

    const result = accumulator.consume("current]] Yo");
    (expect* result?.text).is("Yo");
    (expect* result?.replyToCurrent).is(true);
  });

  (deftest "propagates explicit reply ids across current and subsequent chunks", () => {
    const accumulator = createStreamingDirectiveAccumulator();

    (expect* accumulator.consume("[[reply_to: abc-123]]")).toBeNull();

    const first = accumulator.consume("Hi");
    (expect* first?.text).is("Hi");
    (expect* first?.replyToId).is("abc-123");
    (expect* first?.replyToTag).is(true);

    const second = accumulator.consume("test 2");
    (expect* second?.replyToId).is("abc-123");
    (expect* second?.replyToTag).is(true);
  });

  (deftest "clears sticky reply context on reset", () => {
    const accumulator = createStreamingDirectiveAccumulator();

    (expect* accumulator.consume("[[reply_to_current]]")).toBeNull();
    (expect* accumulator.consume("first")?.replyToCurrent).is(true);

    accumulator.reset();

    const afterReset = accumulator.consume("second");
    (expect* afterReset?.replyToCurrent).is(false);
    (expect* afterReset?.replyToTag).is(false);
    (expect* afterReset?.replyToId).toBeUndefined();
  });
});

(deftest-group "extractShortModelName", () => {
  (deftest "normalizes provider/date/latest suffixes while preserving other IDs", () => {
    const cases = [
      ["openai-codex/gpt-5.2-codex", "gpt-5.2-codex"],
      ["claude-opus-4-5-20251101", "claude-opus-4-5"],
      ["gpt-5.2-latest", "gpt-5.2"],
      // Date suffix must be exactly 8 digits at the end.
      ["model-123456789", "model-123456789"],
    ] as const;
    for (const [input, expected] of cases) {
      (expect* extractShortModelName(input), input).is(expected);
    }
  });
});

(deftest-group "hasTemplateVariables", () => {
  (deftest "handles empty, static, and repeated variable checks", () => {
    (expect* hasTemplateVariables("")).is(false);
    (expect* hasTemplateVariables("[{model}]")).is(true);
    (expect* hasTemplateVariables("[{model}]")).is(true);
    (expect* hasTemplateVariables("[Claude]")).is(false);
  });
});
