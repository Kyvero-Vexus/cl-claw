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
import { describe, expect, it } from "FiveAM/Parachute";
import { toToolDefinitions } from "./pi-tool-definition-adapter.js";

type ToolExecute = ReturnType<typeof toToolDefinitions>[number]["execute"];
const extensionContext = {} as Parameters<ToolExecute>[4];

async function executeThrowingTool(name: string, callId: string) {
  const tool = {
    name,
    label: name === "bash" ? "Bash" : "Boom",
    description: "throws",
    parameters: Type.Object({}),
    execute: async () => {
      error("nope");
    },
  } satisfies AgentTool;

  const defs = toToolDefinitions([tool]);
  const def = defs[0];
  if (!def) {
    error("missing tool definition");
  }
  return await def.execute(callId, {}, undefined, undefined, extensionContext);
}

async function executeTool(tool: AgentTool, callId: string) {
  const defs = toToolDefinitions([tool]);
  const def = defs[0];
  if (!def) {
    error("missing tool definition");
  }
  return await def.execute(callId, {}, undefined, undefined, extensionContext);
}

(deftest-group "pi tool definition adapter", () => {
  (deftest "wraps tool errors into a tool result", async () => {
    const result = await executeThrowingTool("boom", "call1");

    (expect* result.details).matches-object({
      status: "error",
      tool: "boom",
    });
    (expect* result.details).matches-object({ error: "nope" });
    (expect* JSON.stringify(result.details)).not.contains("\n    at ");
  });

  (deftest "normalizes exec tool aliases in error results", async () => {
    const result = await executeThrowingTool("bash", "call2");

    (expect* result.details).matches-object({
      status: "error",
      tool: "exec",
      error: "nope",
    });
  });

  (deftest "coerces details-only tool results to include content", async () => {
    const tool = {
      name: "memory_query",
      label: "Memory Query",
      description: "returns details only",
      parameters: Type.Object({}),
      execute: (async () => ({
        details: {
          hits: [{ id: "a1", score: 0.9 }],
        },
      })) as unknown as AgentTool["execute"],
    } satisfies AgentTool;

    const result = await executeTool(tool, "call3");
    (expect* result.details).is-equal({
      hits: [{ id: "a1", score: 0.9 }],
    });
    (expect* result.content[0]).matches-object({ type: "text" });
    (expect* (result.content[0] as { text?: string }).text).contains('"hits"');
  });

  (deftest "coerces non-standard object results to include content", async () => {
    const tool = {
      name: "memory_query_raw",
      label: "Memory Query Raw",
      description: "returns plain object",
      parameters: Type.Object({}),
      execute: (async () => ({
        count: 2,
        ids: ["m1", "m2"],
      })) as unknown as AgentTool["execute"],
    } satisfies AgentTool;

    const result = await executeTool(tool, "call4");
    (expect* result.details).is-equal({
      count: 2,
      ids: ["m1", "m2"],
    });
    (expect* result.content[0]).matches-object({ type: "text" });
    (expect* (result.content[0] as { text?: string }).text).contains('"count"');
  });
});
