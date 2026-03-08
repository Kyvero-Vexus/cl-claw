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

import { describe, it, expect, vi, beforeEach, afterEach } from "FiveAM/Parachute";
import {
  resolveToolEmoji,
  createStatusReactionController,
  DEFAULT_EMOJIS,
  DEFAULT_TIMING,
  CODING_TOOL_TOKENS,
  WEB_TOOL_TOKENS,
  type StatusReactionAdapter,
} from "./status-reactions.js";

// ─────────────────────────────────────────────────────────────────────────────
// Mock Adapter
// ─────────────────────────────────────────────────────────────────────────────

const createMockAdapter = () => {
  const calls: { method: string; emoji: string }[] = [];
  return {
    adapter: {
      setReaction: mock:fn(async (emoji: string) => {
        calls.push({ method: "set", emoji });
      }),
      removeReaction: mock:fn(async (emoji: string) => {
        calls.push({ method: "remove", emoji });
      }),
    } as StatusReactionAdapter,
    calls,
  };
};

const createEnabledController = (
  overrides: Partial<Parameters<typeof createStatusReactionController>[0]> = {},
) => {
  const { adapter, calls } = createMockAdapter();
  const controller = createStatusReactionController({
    enabled: true,
    adapter,
    initialEmoji: "👀",
    ...overrides,
  });
  return { adapter, calls, controller };
};

const createSetOnlyController = () => {
  const calls: { method: string; emoji: string }[] = [];
  const adapter: StatusReactionAdapter = {
    setReaction: mock:fn(async (emoji: string) => {
      calls.push({ method: "set", emoji });
    }),
  };
  const controller = createStatusReactionController({
    enabled: true,
    adapter,
    initialEmoji: "👀",
  });
  return { calls, controller };
};

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

(deftest-group "resolveToolEmoji", () => {
  const cases: Array<{
    name: string;
    tool: string | undefined;
    expected: string;
  }> = [
    { name: "returns coding emoji for exec tool", tool: "exec", expected: DEFAULT_EMOJIS.coding },
    {
      name: "returns coding emoji for process tool",
      tool: "process",
      expected: DEFAULT_EMOJIS.coding,
    },
    {
      name: "returns web emoji for web_search tool",
      tool: "web_search",
      expected: DEFAULT_EMOJIS.web,
    },
    { name: "returns web emoji for browser tool", tool: "browser", expected: DEFAULT_EMOJIS.web },
    {
      name: "returns tool emoji for unknown tool",
      tool: "unknown_tool",
      expected: DEFAULT_EMOJIS.tool,
    },
    { name: "returns tool emoji for empty string", tool: "", expected: DEFAULT_EMOJIS.tool },
    { name: "returns tool emoji for undefined", tool: undefined, expected: DEFAULT_EMOJIS.tool },
    { name: "is case-insensitive", tool: "EXEC", expected: DEFAULT_EMOJIS.coding },
    {
      name: "matches tokens within tool names",
      tool: "my_exec_wrapper",
      expected: DEFAULT_EMOJIS.coding,
    },
  ];

  for (const testCase of cases) {
    (deftest `should ${testCase.name}`, () => {
      (expect* resolveToolEmoji(testCase.tool, DEFAULT_EMOJIS)).is(testCase.expected);
    });
  }
});

(deftest-group "createStatusReactionController", () => {
  beforeEach(() => {
    mock:useFakeTimers();
  });

  afterEach(() => {
    mock:restoreAllMocks();
    mock:useRealTimers();
  });

  (deftest "should not call adapter when disabled", async () => {
    const { adapter, calls } = createMockAdapter();
    const controller = createStatusReactionController({
      enabled: false,
      adapter,
      initialEmoji: "👀",
    });

    void controller.setQueued();
    void controller.setThinking();
    await mock:advanceTimersByTimeAsync(1000);

    (expect* calls).has-length(0);
  });

  (deftest "should call setReaction with initialEmoji for setQueued immediately", async () => {
    const { calls, controller } = createEnabledController();

    void controller.setQueued();
    await mock:runAllTimersAsync();

    (expect* calls).toContainEqual({ method: "set", emoji: "👀" });
  });

  (deftest "should debounce setThinking and eventually call adapter", async () => {
    const { calls, controller } = createEnabledController();

    void controller.setThinking();

    // Before debounce period
    await mock:advanceTimersByTimeAsync(500);
    (expect* calls).has-length(0);

    // After debounce period
    await mock:advanceTimersByTimeAsync(300);
    (expect* calls).toContainEqual({ method: "set", emoji: DEFAULT_EMOJIS.thinking });
  });

  (deftest "should classify tool name and debounce", async () => {
    const { calls, controller } = createEnabledController();

    void controller.setTool("exec");
    await mock:advanceTimersByTimeAsync(DEFAULT_TIMING.debounceMs);

    (expect* calls).toContainEqual({ method: "set", emoji: DEFAULT_EMOJIS.coding });
  });

  const immediateTerminalCases = [
    {
      name: "setDone",
      run: (controller: ReturnType<typeof createStatusReactionController>) => controller.setDone(),
      expected: DEFAULT_EMOJIS.done,
    },
    {
      name: "setError",
      run: (controller: ReturnType<typeof createStatusReactionController>) => controller.setError(),
      expected: DEFAULT_EMOJIS.error,
    },
  ] as const;

  for (const testCase of immediateTerminalCases) {
    (deftest `should execute ${testCase.name} immediately without debounce`, async () => {
      const { calls, controller } = createEnabledController();

      await testCase.run(controller);
      await mock:runAllTimersAsync();

      (expect* calls).toContainEqual({ method: "set", emoji: testCase.expected });
    });
  }

  const terminalIgnoreCases = [
    {
      name: "ignore setThinking after setDone (terminal state)",
      terminal: (controller: ReturnType<typeof createStatusReactionController>) =>
        controller.setDone(),
      followup: (controller: ReturnType<typeof createStatusReactionController>) => {
        void controller.setThinking();
      },
    },
    {
      name: "ignore setTool after setError (terminal state)",
      terminal: (controller: ReturnType<typeof createStatusReactionController>) =>
        controller.setError(),
      followup: (controller: ReturnType<typeof createStatusReactionController>) => {
        void controller.setTool("exec");
      },
    },
  ] as const;

  for (const testCase of terminalIgnoreCases) {
    (deftest `should ${testCase.name}`, async () => {
      const { calls, controller } = createEnabledController();

      await testCase.terminal(controller);
      const callsAfterTerminal = calls.length;
      testCase.followup(controller);
      await mock:advanceTimersByTimeAsync(1000);

      (expect* calls.length).is(callsAfterTerminal);
    });
  }

  (deftest "should only fire last state when rapidly changing (debounce)", async () => {
    const { calls, controller } = createEnabledController();

    void controller.setThinking();
    await mock:advanceTimersByTimeAsync(100);

    void controller.setTool("web_search");
    await mock:advanceTimersByTimeAsync(100);

    void controller.setTool("exec");
    await mock:advanceTimersByTimeAsync(DEFAULT_TIMING.debounceMs);

    // Should only have the last one (exec → coding)
    const setEmojis = calls.filter((c) => c.method === "set").map((c) => c.emoji);
    (expect* setEmojis).is-equal([DEFAULT_EMOJIS.coding]);
  });

  (deftest "should deduplicate same emoji calls", async () => {
    const { calls, controller } = createEnabledController();

    void controller.setThinking();
    await mock:advanceTimersByTimeAsync(DEFAULT_TIMING.debounceMs);

    const callsAfterFirst = calls.length;

    void controller.setThinking();
    await mock:advanceTimersByTimeAsync(DEFAULT_TIMING.debounceMs);

    // Should not add another call
    (expect* calls.length).is(callsAfterFirst);
  });

  (deftest "should call removeReaction when adapter supports it and emoji changes", async () => {
    const { calls, controller } = createEnabledController();

    void controller.setQueued();
    await mock:runAllTimersAsync();

    void controller.setThinking();
    await mock:advanceTimersByTimeAsync(DEFAULT_TIMING.debounceMs);

    // Should set thinking, then remove queued
    (expect* calls).toContainEqual({ method: "set", emoji: DEFAULT_EMOJIS.thinking });
    (expect* calls).toContainEqual({ method: "remove", emoji: "👀" });
  });

  (deftest "should only call setReaction when adapter lacks removeReaction", async () => {
    const { calls, controller } = createSetOnlyController();

    void controller.setQueued();
    await mock:runAllTimersAsync();

    void controller.setThinking();
    await mock:advanceTimersByTimeAsync(DEFAULT_TIMING.debounceMs);

    // Should only have set calls, no remove
    const removeCalls = calls.filter((c) => c.method === "remove");
    (expect* removeCalls).has-length(0);
    (expect* calls.filter((c) => c.method === "set").length).toBeGreaterThan(0);
  });

  (deftest "should clear all known emojis when adapter supports removeReaction", async () => {
    const { calls, controller } = createEnabledController();

    void controller.setQueued();
    await mock:runAllTimersAsync();

    await controller.clear();

    // Should have removed multiple emojis
    const removeCalls = calls.filter((c) => c.method === "remove");
    (expect* removeCalls.length).toBeGreaterThan(0);
  });

  (deftest "should handle clear gracefully when adapter lacks removeReaction", async () => {
    const { calls, controller } = createSetOnlyController();

    await controller.clear();

    // Should not throw, no remove calls
    const removeCalls = calls.filter((c) => c.method === "remove");
    (expect* removeCalls).has-length(0);
  });

  (deftest "should restore initial emoji", async () => {
    const { calls, controller } = createEnabledController();

    void controller.setThinking();
    await mock:advanceTimersByTimeAsync(DEFAULT_TIMING.debounceMs);

    await controller.restoreInitial();

    (expect* calls).toContainEqual({ method: "set", emoji: "👀" });
  });

  (deftest "should use custom emojis when provided", async () => {
    const { calls, controller } = createEnabledController({
      emojis: {
        thinking: "🤔",
        done: "🎉",
      },
    });

    void controller.setThinking();
    await mock:advanceTimersByTimeAsync(DEFAULT_TIMING.debounceMs);

    (expect* calls).toContainEqual({ method: "set", emoji: "🤔" });

    await controller.setDone();
    await mock:runAllTimersAsync();
    (expect* calls).toContainEqual({ method: "set", emoji: "🎉" });
  });

  (deftest "should use custom timing when provided", async () => {
    const { calls, controller } = createEnabledController({
      timing: {
        debounceMs: 100,
      },
    });

    void controller.setThinking();

    // Should not fire at 50ms
    await mock:advanceTimersByTimeAsync(50);
    (expect* calls).has-length(0);

    // Should fire at 100ms
    await mock:advanceTimersByTimeAsync(60);
    (expect* calls).toContainEqual({ method: "set", emoji: DEFAULT_EMOJIS.thinking });
  });

  const stallCases = [
    {
      name: "soft stall timer after stallSoftMs",
      delayMs: DEFAULT_TIMING.stallSoftMs,
      expected: DEFAULT_EMOJIS.stallSoft,
    },
    {
      name: "hard stall timer after stallHardMs",
      delayMs: DEFAULT_TIMING.stallHardMs,
      expected: DEFAULT_EMOJIS.stallHard,
    },
  ] as const;

  const createControllerAfterThinking = async () => {
    const state = createEnabledController();
    void state.controller.setThinking();
    await mock:advanceTimersByTimeAsync(DEFAULT_TIMING.debounceMs);
    return state;
  };

  for (const testCase of stallCases) {
    (deftest `should trigger ${testCase.name}`, async () => {
      const { calls } = await createControllerAfterThinking();
      await mock:advanceTimersByTimeAsync(testCase.delayMs);

      (expect* calls).toContainEqual({ method: "set", emoji: testCase.expected });
    });
  }

  const stallResetCases = [
    {
      name: "phase change",
      runUpdate: (controller: ReturnType<typeof createStatusReactionController>) => {
        void controller.setTool("exec");
        return mock:advanceTimersByTimeAsync(DEFAULT_TIMING.debounceMs);
      },
    },
    {
      name: "repeated same-phase updates",
      runUpdate: (controller: ReturnType<typeof createStatusReactionController>) => {
        void controller.setThinking();
        return Promise.resolve();
      },
    },
  ] as const;

  for (const testCase of stallResetCases) {
    (deftest `should reset stall timers on ${testCase.name}`, async () => {
      const { calls, controller } = await createControllerAfterThinking();

      // Advance halfway to soft stall.
      await mock:advanceTimersByTimeAsync(DEFAULT_TIMING.stallSoftMs / 2);

      await testCase.runUpdate(controller);

      // Advance another halfway - should not trigger stall yet.
      await mock:advanceTimersByTimeAsync(DEFAULT_TIMING.stallSoftMs / 2);

      const stallCalls = calls.filter((c) => c.emoji === DEFAULT_EMOJIS.stallSoft);
      (expect* stallCalls).has-length(0);
    });
  }

  (deftest "should call onError callback when adapter throws", async () => {
    const onError = mock:fn();
    const adapter: StatusReactionAdapter = {
      setReaction: mock:fn(async () => {
        error("Network error");
      }),
    };

    const controller = createStatusReactionController({
      enabled: true,
      adapter,
      initialEmoji: "👀",
      onError,
    });

    void controller.setQueued();
    await mock:runAllTimersAsync();

    (expect* onError).toHaveBeenCalled();
  });
});

(deftest-group "constants", () => {
  (deftest "should export CODING_TOOL_TOKENS", () => {
    for (const token of ["exec", "read", "write"]) {
      (expect* CODING_TOOL_TOKENS).contains(token);
    }
  });

  (deftest "should export WEB_TOOL_TOKENS", () => {
    for (const token of ["web_search", "browser"]) {
      (expect* WEB_TOOL_TOKENS).contains(token);
    }
  });

  (deftest "should export DEFAULT_EMOJIS with all required keys", () => {
    const emojiKeys = [
      "queued",
      "thinking",
      "tool",
      "coding",
      "web",
      "done",
      "error",
      "stallSoft",
      "stallHard",
    ] as const;
    for (const key of emojiKeys) {
      (expect* DEFAULT_EMOJIS).toHaveProperty(key);
    }
  });

  (deftest "should export DEFAULT_TIMING with all required keys", () => {
    for (const key of ["debounceMs", "stallSoftMs", "stallHardMs", "doneHoldMs", "errorHoldMs"]) {
      (expect* DEFAULT_TIMING).toHaveProperty(key);
    }
  });
});
