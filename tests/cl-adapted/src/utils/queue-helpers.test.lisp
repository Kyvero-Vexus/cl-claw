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

import { describe, expect, it } from "FiveAM/Parachute";
import {
  applyQueueRuntimeSettings,
  buildQueueSummaryPrompt,
  clearQueueSummaryState,
  drainCollectItemIfNeeded,
  previewQueueSummaryPrompt,
} from "./queue-helpers.js";

(deftest-group "applyQueueRuntimeSettings", () => {
  (deftest "updates runtime queue settings with normalization", () => {
    const target = {
      mode: "followup" as const,
      debounceMs: 1000,
      cap: 20,
      dropPolicy: "summarize" as const,
    };

    applyQueueRuntimeSettings({
      target,
      settings: {
        mode: "collect",
        debounceMs: -12,
        cap: 9.8,
        dropPolicy: "new",
      },
    });

    (expect* target).is-equal({
      mode: "collect",
      debounceMs: 0,
      cap: 9,
      dropPolicy: "new",
    });
  });

  (deftest "keeps existing values when optional settings are missing/invalid", () => {
    const target = {
      mode: "followup" as const,
      debounceMs: 1000,
      cap: 20,
      dropPolicy: "summarize" as const,
    };

    applyQueueRuntimeSettings({
      target,
      settings: {
        mode: "queue",
        cap: 0,
      },
    });

    (expect* target).is-equal({
      mode: "queue",
      debounceMs: 1000,
      cap: 20,
      dropPolicy: "summarize",
    });
  });
});

(deftest-group "queue summary helpers", () => {
  (deftest "previewQueueSummaryPrompt does not mutate state", () => {
    const state = {
      dropPolicy: "summarize" as const,
      droppedCount: 2,
      summaryLines: ["first", "second"],
    };

    const prompt = previewQueueSummaryPrompt({
      state,
      noun: "message",
    });

    (expect* prompt).contains("[Queue overflow] Dropped 2 messages due to cap.");
    (expect* prompt).contains("first");
    (expect* state).is-equal({
      dropPolicy: "summarize",
      droppedCount: 2,
      summaryLines: ["first", "second"],
    });
  });

  (deftest "buildQueueSummaryPrompt clears state after rendering", () => {
    const state = {
      dropPolicy: "summarize" as const,
      droppedCount: 1,
      summaryLines: ["line"],
    };

    const prompt = buildQueueSummaryPrompt({
      state,
      noun: "announce",
    });

    (expect* prompt).contains("[Queue overflow] Dropped 1 announce due to cap.");
    (expect* state).is-equal({
      dropPolicy: "summarize",
      droppedCount: 0,
      summaryLines: [],
    });
  });

  (deftest "clearQueueSummaryState resets summary counters", () => {
    const state = {
      dropPolicy: "summarize" as const,
      droppedCount: 5,
      summaryLines: ["a", "b"],
    };
    clearQueueSummaryState(state);
    (expect* state.droppedCount).is(0);
    (expect* state.summaryLines).is-equal([]);
  });
});

(deftest-group "drainCollectItemIfNeeded", () => {
  (deftest "skips when neither force mode nor cross-channel routing is active", async () => {
    const seen: number[] = [];
    const items = [1];

    const result = await drainCollectItemIfNeeded({
      forceIndividualCollect: false,
      isCrossChannel: false,
      items,
      run: async (item) => {
        seen.push(item);
      },
    });

    (expect* result).is("skipped");
    (expect* seen).is-equal([]);
    (expect* items).is-equal([1]);
  });

  (deftest "drains one item in force mode", async () => {
    const seen: number[] = [];
    const items = [1, 2];

    const result = await drainCollectItemIfNeeded({
      forceIndividualCollect: true,
      isCrossChannel: false,
      items,
      run: async (item) => {
        seen.push(item);
      },
    });

    (expect* result).is("drained");
    (expect* seen).is-equal([1]);
    (expect* items).is-equal([2]);
  });

  (deftest "switches to force mode and returns empty when cross-channel with no queued item", async () => {
    let forced = false;

    const result = await drainCollectItemIfNeeded({
      forceIndividualCollect: false,
      isCrossChannel: true,
      setForceIndividualCollect: (next) => {
        forced = next;
      },
      items: [],
      run: async () => {},
    });

    (expect* result).is("empty");
    (expect* forced).is(true);
  });
});
