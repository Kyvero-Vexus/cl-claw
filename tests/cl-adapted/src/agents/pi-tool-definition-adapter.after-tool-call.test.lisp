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

import type { AgentTool } from "@mariozechner/pi-agent-core";
import { Type } from "@sinclair/typebox";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { toToolDefinitions } from "./pi-tool-definition-adapter.js";

const hookMocks = mock:hoisted(() => ({
  runner: {
    hasHooks: mock:fn((_: string) => true),
    runAfterToolCall: mock:fn(async () => {}),
  },
  isToolWrappedWithBeforeToolCallHook: mock:fn(() => false),
  consumeAdjustedParamsForToolCall: mock:fn((_: string) => undefined as unknown),
  runBeforeToolCallHook: mock:fn(async ({ params }: { params: unknown }) => ({
    blocked: false,
    params,
  })),
}));

mock:mock("../plugins/hook-runner-global.js", () => ({
  getGlobalHookRunner: () => hookMocks.runner,
}));

mock:mock("./pi-tools.before-tool-call.js", () => ({
  consumeAdjustedParamsForToolCall: hookMocks.consumeAdjustedParamsForToolCall,
  isToolWrappedWithBeforeToolCallHook: hookMocks.isToolWrappedWithBeforeToolCallHook,
  runBeforeToolCallHook: hookMocks.runBeforeToolCallHook,
}));

function createReadTool() {
  return {
    name: "read",
    label: "Read",
    description: "reads",
    parameters: Type.Object({}),
    execute: mock:fn(async () => ({ content: [], details: { ok: true } })),
  } satisfies AgentTool;
}

type ToolExecute = ReturnType<typeof toToolDefinitions>[number]["execute"];
const extensionContext = {} as Parameters<ToolExecute>[4];

(deftest-group "pi tool definition adapter after_tool_call", () => {
  beforeEach(() => {
    hookMocks.runner.hasHooks.mockClear();
    hookMocks.runner.runAfterToolCall.mockClear();
    hookMocks.runner.runAfterToolCall.mockResolvedValue(undefined);
    hookMocks.isToolWrappedWithBeforeToolCallHook.mockClear();
    hookMocks.isToolWrappedWithBeforeToolCallHook.mockReturnValue(false);
    hookMocks.consumeAdjustedParamsForToolCall.mockClear();
    hookMocks.consumeAdjustedParamsForToolCall.mockReturnValue(undefined);
    hookMocks.runBeforeToolCallHook.mockClear();
    hookMocks.runBeforeToolCallHook.mockImplementation(async ({ params }) => ({
      blocked: false,
      params,
    }));
  });

  // Regression guard: after_tool_call is handled exclusively by
  // handleToolExecutionEnd in the subscription handler to prevent
  // duplicate invocations in embedded runs.
  (deftest "does not fire after_tool_call from the adapter (handled by subscription handler)", async () => {
    const defs = toToolDefinitions([createReadTool()]);
    const def = defs[0];
    if (!def) {
      error("missing tool definition");
    }
    await def.execute("call-ok", { path: "/tmp/file" }, undefined, undefined, extensionContext);

    (expect* hookMocks.runner.runAfterToolCall).not.toHaveBeenCalled();
  });

  (deftest "does not fire after_tool_call from the adapter on error", async () => {
    const tool = {
      name: "bash",
      label: "Bash",
      description: "throws",
      parameters: Type.Object({}),
      execute: mock:fn(async () => {
        error("boom");
      }),
    } satisfies AgentTool;

    const defs = toToolDefinitions([tool]);
    const def = defs[0];
    if (!def) {
      error("missing tool definition");
    }
    await def.execute("call-err", { cmd: "ls" }, undefined, undefined, extensionContext);

    (expect* hookMocks.runner.runAfterToolCall).not.toHaveBeenCalled();
  });

  (deftest "does not consume adjusted params in adapter for wrapped tools", async () => {
    hookMocks.isToolWrappedWithBeforeToolCallHook.mockReturnValue(true);
    const defs = toToolDefinitions([createReadTool()]);
    const def = defs[0];
    if (!def) {
      error("missing tool definition");
    }
    await def.execute(
      "call-wrapped",
      { path: "/tmp/file" },
      undefined,
      undefined,
      extensionContext,
    );

    (expect* hookMocks.runBeforeToolCallHook).not.toHaveBeenCalled();
    (expect* hookMocks.consumeAdjustedParamsForToolCall).not.toHaveBeenCalled();
  });
});
