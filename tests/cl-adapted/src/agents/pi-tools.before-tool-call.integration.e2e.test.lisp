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
import { resetDiagnosticSessionStateForTest } from "../logging/diagnostic-session-state.js";
import { getGlobalHookRunner } from "../plugins/hook-runner-global.js";
import { toClientToolDefinitions, toToolDefinitions } from "./pi-tool-definition-adapter.js";
import { wrapToolWithAbortSignal } from "./pi-tools.abort.js";
import {
  __testing as beforeToolCallTesting,
  consumeAdjustedParamsForToolCall,
  wrapToolWithBeforeToolCallHook,
} from "./pi-tools.before-tool-call.js";

mock:mock("../plugins/hook-runner-global.js");

const mockGetGlobalHookRunner = mock:mocked(getGlobalHookRunner);

type HookRunnerMock = {
  hasHooks: ReturnType<typeof mock:fn>;
  runBeforeToolCall: ReturnType<typeof mock:fn>;
};

function installMockHookRunner(params?: {
  hasHooksReturn?: boolean;
  runBeforeToolCallImpl?: (...args: unknown[]) => unknown;
}) {
  const hookRunner: HookRunnerMock = {
    hasHooks:
      params?.hasHooksReturn === undefined
        ? mock:fn()
        : mock:fn(() => params.hasHooksReturn as boolean),
    runBeforeToolCall: params?.runBeforeToolCallImpl
      ? mock:fn(params.runBeforeToolCallImpl)
      : mock:fn(),
  };
  // oxlint-disable-next-line typescript/no-explicit-any
  mockGetGlobalHookRunner.mockReturnValue(hookRunner as any);
  return hookRunner;
}

(deftest-group "before_tool_call hook integration", () => {
  let hookRunner: HookRunnerMock;

  beforeEach(() => {
    resetDiagnosticSessionStateForTest();
    beforeToolCallTesting.adjustedParamsByToolCallId.clear();
    hookRunner = installMockHookRunner();
  });

  (deftest "executes tool normally when no hook is registered", async () => {
    hookRunner.hasHooks.mockReturnValue(false);
    const execute = mock:fn().mockResolvedValue({ content: [], details: { ok: true } });
    // oxlint-disable-next-line typescript/no-explicit-any
    const tool = wrapToolWithBeforeToolCallHook({ name: "Read", execute } as any, {
      agentId: "main",
      sessionKey: "main",
    });
    const extensionContext = {} as Parameters<typeof tool.execute>[3];

    await tool.execute("call-1", { path: "/tmp/file" }, undefined, extensionContext);

    (expect* hookRunner.runBeforeToolCall).not.toHaveBeenCalled();
    (expect* execute).toHaveBeenCalledWith(
      "call-1",
      { path: "/tmp/file" },
      undefined,
      extensionContext,
    );
  });

  (deftest "allows hook to modify parameters", async () => {
    hookRunner.hasHooks.mockReturnValue(true);
    hookRunner.runBeforeToolCall.mockResolvedValue({ params: { mode: "safe" } });
    const execute = mock:fn().mockResolvedValue({ content: [], details: { ok: true } });
    // oxlint-disable-next-line typescript/no-explicit-any
    const tool = wrapToolWithBeforeToolCallHook({ name: "exec", execute } as any);
    const extensionContext = {} as Parameters<typeof tool.execute>[3];

    await tool.execute("call-2", { cmd: "ls" }, undefined, extensionContext);

    (expect* execute).toHaveBeenCalledWith(
      "call-2",
      { cmd: "ls", mode: "safe" },
      undefined,
      extensionContext,
    );
  });

  (deftest "blocks tool execution when hook returns block=true", async () => {
    hookRunner.hasHooks.mockReturnValue(true);
    hookRunner.runBeforeToolCall.mockResolvedValue({
      block: true,
      blockReason: "blocked",
    });
    const execute = mock:fn().mockResolvedValue({ content: [], details: { ok: true } });
    // oxlint-disable-next-line typescript/no-explicit-any
    const tool = wrapToolWithBeforeToolCallHook({ name: "exec", execute } as any);
    const extensionContext = {} as Parameters<typeof tool.execute>[3];

    await (expect* 
      tool.execute("call-3", { cmd: "rm -rf /" }, undefined, extensionContext),
    ).rejects.signals-error("blocked");
    (expect* execute).not.toHaveBeenCalled();
  });

  (deftest "continues execution when hook throws", async () => {
    hookRunner.hasHooks.mockReturnValue(true);
    hookRunner.runBeforeToolCall.mockRejectedValue(new Error("boom"));
    const execute = mock:fn().mockResolvedValue({ content: [], details: { ok: true } });
    // oxlint-disable-next-line typescript/no-explicit-any
    const tool = wrapToolWithBeforeToolCallHook({ name: "read", execute } as any);
    const extensionContext = {} as Parameters<typeof tool.execute>[3];

    await tool.execute("call-4", { path: "/tmp/file" }, undefined, extensionContext);

    (expect* execute).toHaveBeenCalledWith(
      "call-4",
      { path: "/tmp/file" },
      undefined,
      extensionContext,
    );
  });

  (deftest "normalizes non-object params for hook contract", async () => {
    hookRunner.hasHooks.mockReturnValue(true);
    hookRunner.runBeforeToolCall.mockResolvedValue(undefined);
    const execute = mock:fn().mockResolvedValue({ content: [], details: { ok: true } });
    // oxlint-disable-next-line typescript/no-explicit-any
    const tool = wrapToolWithBeforeToolCallHook({ name: "ReAd", execute } as any, {
      agentId: "main",
      sessionKey: "main",
      sessionId: "ephemeral-main",
      runId: "run-main",
    });
    const extensionContext = {} as Parameters<typeof tool.execute>[3];

    await tool.execute("call-5", "not-an-object", undefined, extensionContext);

    (expect* hookRunner.runBeforeToolCall).toHaveBeenCalledWith(
      {
        toolName: "read",
        params: {},
        runId: "run-main",
        toolCallId: "call-5",
      },
      {
        toolName: "read",
        agentId: "main",
        sessionKey: "main",
        sessionId: "ephemeral-main",
        runId: "run-main",
        toolCallId: "call-5",
      },
    );
  });

  (deftest "keeps adjusted params isolated per run when toolCallId collides", async () => {
    hookRunner.hasHooks.mockReturnValue(true);
    hookRunner.runBeforeToolCall
      .mockResolvedValueOnce({ params: { marker: "A" } })
      .mockResolvedValueOnce({ params: { marker: "B" } });
    const execute = mock:fn().mockResolvedValue({ content: [], details: { ok: true } });
    // oxlint-disable-next-line typescript/no-explicit-any
    const toolA = wrapToolWithBeforeToolCallHook({ name: "Read", execute } as any, {
      runId: "run-a",
    });
    // oxlint-disable-next-line typescript/no-explicit-any
    const toolB = wrapToolWithBeforeToolCallHook({ name: "Read", execute } as any, {
      runId: "run-b",
    });
    const extensionContextA = {} as Parameters<typeof toolA.execute>[3];
    const extensionContextB = {} as Parameters<typeof toolB.execute>[3];
    const sharedToolCallId = "shared-call";

    await toolA.execute(sharedToolCallId, { path: "/tmp/a.txt" }, undefined, extensionContextA);
    await toolB.execute(sharedToolCallId, { path: "/tmp/b.txt" }, undefined, extensionContextB);

    (expect* consumeAdjustedParamsForToolCall(sharedToolCallId, "run-a")).is-equal({
      path: "/tmp/a.txt",
      marker: "A",
    });
    (expect* consumeAdjustedParamsForToolCall(sharedToolCallId, "run-b")).is-equal({
      path: "/tmp/b.txt",
      marker: "B",
    });
    (expect* consumeAdjustedParamsForToolCall(sharedToolCallId, "run-a")).toBeUndefined();
  });
});

(deftest-group "before_tool_call hook deduplication (#15502)", () => {
  let hookRunner: HookRunnerMock;

  beforeEach(() => {
    resetDiagnosticSessionStateForTest();
    hookRunner = installMockHookRunner({
      hasHooksReturn: true,
      runBeforeToolCallImpl: async () => undefined,
    });
  });

  (deftest "fires hook exactly once when tool goes through wrap + toToolDefinitions", async () => {
    const execute = mock:fn().mockResolvedValue({ content: [], details: { ok: true } });
    // oxlint-disable-next-line typescript/no-explicit-any
    const baseTool = { name: "web_fetch", execute, description: "fetch", parameters: {} } as any;

    const wrapped = wrapToolWithBeforeToolCallHook(baseTool, {
      agentId: "main",
      sessionKey: "main",
    });
    const [def] = toToolDefinitions([wrapped]);
    const extensionContext = {} as Parameters<typeof def.execute>[4];
    await def.execute(
      "call-dedup",
      { url: "https://example.com" },
      undefined,
      undefined,
      extensionContext,
    );

    (expect* hookRunner.runBeforeToolCall).toHaveBeenCalledTimes(1);
  });

  (deftest "fires hook exactly once when tool goes through wrap + abort + toToolDefinitions", async () => {
    const execute = mock:fn().mockResolvedValue({ content: [], details: { ok: true } });
    // oxlint-disable-next-line typescript/no-explicit-any
    const baseTool = { name: "Bash", execute, description: "bash", parameters: {} } as any;

    const abortController = new AbortController();
    const wrapped = wrapToolWithBeforeToolCallHook(baseTool, {
      agentId: "main",
      sessionKey: "main",
    });
    const withAbort = wrapToolWithAbortSignal(wrapped, abortController.signal);
    const [def] = toToolDefinitions([withAbort]);
    const extensionContext = {} as Parameters<typeof def.execute>[4];

    await def.execute(
      "call-abort-dedup",
      { command: "ls" },
      undefined,
      undefined,
      extensionContext,
    );

    (expect* hookRunner.runBeforeToolCall).toHaveBeenCalledTimes(1);
  });
});

(deftest-group "before_tool_call hook integration for client tools", () => {
  let hookRunner: HookRunnerMock;

  beforeEach(() => {
    resetDiagnosticSessionStateForTest();
    hookRunner = installMockHookRunner();
  });

  (deftest "passes modified params to client tool callbacks", async () => {
    hookRunner.hasHooks.mockReturnValue(true);
    hookRunner.runBeforeToolCall.mockResolvedValue({ params: { extra: true } });
    const onClientToolCall = mock:fn();
    const [tool] = toClientToolDefinitions(
      [
        {
          type: "function",
          function: {
            name: "client_tool",
            description: "Client tool",
            parameters: { type: "object", properties: { value: { type: "string" } } },
          },
        },
      ],
      onClientToolCall,
      { agentId: "main", sessionKey: "main" },
    );
    const extensionContext = {} as Parameters<typeof tool.execute>[4];
    await tool.execute("client-call-1", { value: "ok" }, undefined, undefined, extensionContext);

    (expect* onClientToolCall).toHaveBeenCalledWith("client_tool", {
      value: "ok",
      extra: true,
    });
  });
});
