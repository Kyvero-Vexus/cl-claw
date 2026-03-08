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
import {
  onDiagnosticEvent,
  resetDiagnosticEventsForTest,
  type DiagnosticToolLoopEvent,
} from "../infra/diagnostic-events.js";
import { resetDiagnosticSessionStateForTest } from "../logging/diagnostic-session-state.js";
import { getGlobalHookRunner } from "../plugins/hook-runner-global.js";
import { wrapToolWithBeforeToolCallHook } from "./pi-tools.before-tool-call.js";
import { CRITICAL_THRESHOLD, GLOBAL_CIRCUIT_BREAKER_THRESHOLD } from "./tool-loop-detection.js";
import type { AnyAgentTool } from "./tools/common.js";

mock:mock("../plugins/hook-runner-global.js");

const mockGetGlobalHookRunner = mock:mocked(getGlobalHookRunner);

(deftest-group "before_tool_call loop detection behavior", () => {
  let hookRunner: {
    hasHooks: ReturnType<typeof mock:fn>;
    runBeforeToolCall: ReturnType<typeof mock:fn>;
  };
  const enabledLoopDetectionContext = {
    agentId: "main",
    sessionKey: "main",
    loopDetection: { enabled: true },
  };

  const disabledLoopDetectionContext = {
    agentId: "main",
    sessionKey: "main",
    loopDetection: { enabled: false },
  };

  beforeEach(() => {
    resetDiagnosticSessionStateForTest();
    resetDiagnosticEventsForTest();
    hookRunner = {
      hasHooks: mock:fn(),
      runBeforeToolCall: mock:fn(),
    };
    // oxlint-disable-next-line typescript/no-explicit-any
    mockGetGlobalHookRunner.mockReturnValue(hookRunner as any);
    hookRunner.hasHooks.mockReturnValue(false);
  });

  function createWrappedTool(
    name: string,
    execute: ReturnType<typeof mock:fn>,
    loopDetectionContext = enabledLoopDetectionContext,
  ) {
    return wrapToolWithBeforeToolCallHook(
      { name, execute } as unknown as AnyAgentTool,
      loopDetectionContext,
    );
  }

  async function withToolLoopEvents(
    run: (emitted: DiagnosticToolLoopEvent[]) => deferred-result<void>,
    filter: (evt: DiagnosticToolLoopEvent) => boolean = () => true,
  ) {
    const emitted: DiagnosticToolLoopEvent[] = [];
    const stop = onDiagnosticEvent((evt) => {
      if (evt.type === "tool.loop" && filter(evt)) {
        emitted.push(evt);
      }
    });
    try {
      await run(emitted);
    } finally {
      stop();
    }
  }

  function createPingPongTools(options?: { withProgress?: boolean }) {
    const readExecute = options?.withProgress
      ? mock:fn().mockImplementation(async (toolCallId: string) => ({
          content: [{ type: "text", text: `read ${toolCallId}` }],
          details: { ok: true },
        }))
      : mock:fn().mockResolvedValue({
          content: [{ type: "text", text: "read ok" }],
          details: { ok: true },
        });
    const listExecute = options?.withProgress
      ? mock:fn().mockImplementation(async (toolCallId: string) => ({
          content: [{ type: "text", text: `list ${toolCallId}` }],
          details: { ok: true },
        }))
      : mock:fn().mockResolvedValue({
          content: [{ type: "text", text: "list ok" }],
          details: { ok: true },
        });
    return {
      readTool: createWrappedTool("read", readExecute),
      listTool: createWrappedTool("list", listExecute),
    };
  }

  async function runPingPongSequence(
    readTool: ReturnType<typeof createWrappedTool>,
    listTool: ReturnType<typeof createWrappedTool>,
    count: number,
  ) {
    for (let i = 0; i < count; i += 1) {
      if (i % 2 === 0) {
        await readTool.execute(`read-${i}`, { path: "/a.txt" }, undefined, undefined);
      } else {
        await listTool.execute(`list-${i}`, { dir: "/workspace" }, undefined, undefined);
      }
    }
  }

  function createGenericReadRepeatFixture() {
    const execute = mock:fn().mockResolvedValue({
      content: [{ type: "text", text: "same output" }],
      details: { ok: true },
    });
    return {
      tool: createWrappedTool("read", execute),
      params: { path: "/tmp/file" },
    };
  }

  function createNoProgressProcessFixture(sessionId: string) {
    const execute = mock:fn().mockResolvedValue({
      content: [{ type: "text", text: "(no new output)\n\nProcess still running." }],
      details: { status: "running", aggregated: "steady" },
    });
    return {
      tool: createWrappedTool("process", execute),
      params: { action: "poll", sessionId },
    };
  }

  function expectCriticalLoopEvent(
    loopEvent: DiagnosticToolLoopEvent | undefined,
    params: {
      detector: "ping_pong" | "known_poll_no_progress";
      toolName: string;
      count?: number;
    },
  ) {
    (expect* loopEvent?.type).is("tool.loop");
    (expect* loopEvent?.level).is("critical");
    (expect* loopEvent?.action).is("block");
    (expect* loopEvent?.detector).is(params.detector);
    (expect* loopEvent?.count).is(params.count ?? CRITICAL_THRESHOLD);
    (expect* loopEvent?.toolName).is(params.toolName);
  }

  (deftest "blocks known poll loops when no progress repeats", async () => {
    const { tool, params } = createNoProgressProcessFixture("sess-1");

    for (let i = 0; i < CRITICAL_THRESHOLD; i += 1) {
      await (expect* tool.execute(`poll-${i}`, params, undefined, undefined)).resolves.toBeDefined();
    }

    await (expect* 
      tool.execute(`poll-${CRITICAL_THRESHOLD}`, params, undefined, undefined),
    ).rejects.signals-error("CRITICAL");
  });

  (deftest "does nothing when loopDetection.enabled is false", async () => {
    const execute = mock:fn().mockResolvedValue({
      content: [{ type: "text", text: "(no new output)\n\nProcess still running." }],
      details: { status: "running", aggregated: "steady" },
    });
    // oxlint-disable-next-line typescript/no-explicit-any
    const tool = wrapToolWithBeforeToolCallHook({ name: "process", execute } as any, {
      ...disabledLoopDetectionContext,
    });
    const params = { action: "poll", sessionId: "sess-off" };

    for (let i = 0; i < CRITICAL_THRESHOLD; i += 1) {
      await (expect* tool.execute(`poll-${i}`, params, undefined, undefined)).resolves.toBeDefined();
    }
  });

  (deftest "does not block known poll loops when output progresses", async () => {
    const execute = mock:fn().mockImplementation(async (toolCallId: string) => {
      return {
        content: [{ type: "text", text: `output ${toolCallId}` }],
        details: { status: "running", aggregated: `output ${toolCallId}` },
      };
    });
    const tool = createWrappedTool("process", execute);
    const params = { action: "poll", sessionId: "sess-2" };

    for (let i = 0; i < CRITICAL_THRESHOLD + 5; i += 1) {
      await (expect* 
        tool.execute(`poll-progress-${i}`, params, undefined, undefined),
      ).resolves.toBeDefined();
    }
  });

  (deftest "keeps generic repeated calls warn-only below global breaker", async () => {
    const { tool, params } = createGenericReadRepeatFixture();

    for (let i = 0; i < CRITICAL_THRESHOLD + 5; i += 1) {
      await (expect* tool.execute(`read-${i}`, params, undefined, undefined)).resolves.toBeDefined();
    }
  });

  (deftest "blocks generic repeated no-progress calls at global breaker threshold", async () => {
    const { tool, params } = createGenericReadRepeatFixture();

    for (let i = 0; i < GLOBAL_CIRCUIT_BREAKER_THRESHOLD; i += 1) {
      await (expect* tool.execute(`read-${i}`, params, undefined, undefined)).resolves.toBeDefined();
    }

    await (expect* 
      tool.execute(`read-${GLOBAL_CIRCUIT_BREAKER_THRESHOLD}`, params, undefined, undefined),
    ).rejects.signals-error("global circuit breaker");
  });

  (deftest "coalesces repeated generic warning events into threshold buckets", async () => {
    await withToolLoopEvents(
      async (emitted) => {
        const { tool, params } = createGenericReadRepeatFixture();

        for (let i = 0; i < 21; i += 1) {
          await tool.execute(`read-bucket-${i}`, params, undefined, undefined);
        }

        const genericWarns = emitted.filter((evt) => evt.detector === "generic_repeat");
        (expect* genericWarns.map((evt) => evt.count)).is-equal([10, 20]);
      },
      (evt) => evt.level === "warning",
    );
  });

  (deftest "emits structured warning diagnostic events for ping-pong loops", async () => {
    await withToolLoopEvents(async (emitted) => {
      const { readTool, listTool } = createPingPongTools();
      await runPingPongSequence(readTool, listTool, 9);

      await listTool.execute("list-9", { dir: "/workspace" }, undefined, undefined);
      await readTool.execute("read-10", { path: "/a.txt" }, undefined, undefined);
      await listTool.execute("list-11", { dir: "/workspace" }, undefined, undefined);

      const pingPongWarns = emitted.filter(
        (evt) => evt.level === "warning" && evt.detector === "ping_pong",
      );
      (expect* pingPongWarns).has-length(1);
      const loopEvent = pingPongWarns[0];
      (expect* loopEvent?.type).is("tool.loop");
      (expect* loopEvent?.level).is("warning");
      (expect* loopEvent?.action).is("warn");
      (expect* loopEvent?.detector).is("ping_pong");
      (expect* loopEvent?.count).is(10);
      (expect* loopEvent?.toolName).is("list");
    });
  });

  (deftest "blocks ping-pong loops at critical threshold and emits critical diagnostic events", async () => {
    await withToolLoopEvents(async (emitted) => {
      const { readTool, listTool } = createPingPongTools();
      await runPingPongSequence(readTool, listTool, CRITICAL_THRESHOLD - 1);

      await (expect* 
        listTool.execute(
          `list-${CRITICAL_THRESHOLD - 1}`,
          { dir: "/workspace" },
          undefined,
          undefined,
        ),
      ).rejects.signals-error("CRITICAL");

      const loopEvent = emitted.at(-1);
      expectCriticalLoopEvent(loopEvent, {
        detector: "ping_pong",
        toolName: "list",
      });
    });
  });

  (deftest "does not block ping-pong at critical threshold when outcomes are progressing", async () => {
    await withToolLoopEvents(async (emitted) => {
      const { readTool, listTool } = createPingPongTools({ withProgress: true });
      await runPingPongSequence(readTool, listTool, CRITICAL_THRESHOLD - 1);

      await (expect* 
        listTool.execute(
          `list-${CRITICAL_THRESHOLD - 1}`,
          { dir: "/workspace" },
          undefined,
          undefined,
        ),
      ).resolves.toBeDefined();

      const criticalPingPong = emitted.find(
        (evt) => evt.level === "critical" && evt.detector === "ping_pong",
      );
      (expect* criticalPingPong).toBeUndefined();
      const warningPingPong = emitted.find(
        (evt) => evt.level === "warning" && evt.detector === "ping_pong",
      );
      (expect* warningPingPong).is-truthy();
    });
  });

  (deftest "emits structured critical diagnostic events when blocking loops", async () => {
    await withToolLoopEvents(async (emitted) => {
      const { tool, params } = createNoProgressProcessFixture("sess-crit");

      for (let i = 0; i < CRITICAL_THRESHOLD; i += 1) {
        await tool.execute(`poll-${i}`, params, undefined, undefined);
      }

      await (expect* 
        tool.execute(`poll-${CRITICAL_THRESHOLD}`, params, undefined, undefined),
      ).rejects.signals-error("CRITICAL");

      const loopEvent = emitted.at(-1);
      expectCriticalLoopEvent(loopEvent, {
        detector: "known_poll_no_progress",
        toolName: "process",
      });
    });
  });
});
