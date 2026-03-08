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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createSubscribedSessionHarness } from "./pi-embedded-subscribe.e2e-harness.js";

(deftest-group "subscribeEmbeddedPiSession", () => {
  (deftest "includes canvas action metadata in tool summaries", async () => {
    const onToolResult = mock:fn();

    const toolHarness = createSubscribedSessionHarness({
      runId: "run-canvas-tool",
      verboseLevel: "on",
      onToolResult,
    });

    toolHarness.emit({
      type: "tool_execution_start",
      toolName: "canvas",
      toolCallId: "tool-canvas-1",
      args: { action: "a2ui_push", jsonlPath: "/tmp/a2ui.jsonl" },
    });

    // Wait for async handler to complete
    await Promise.resolve();

    (expect* onToolResult).toHaveBeenCalledTimes(1);
    const payload = onToolResult.mock.calls[0][0];
    (expect* payload.text).contains("🖼️");
    (expect* payload.text).contains("Canvas");
    (expect* payload.text).contains("/tmp/a2ui.jsonl");
  });
  (deftest "skips tool summaries when shouldEmitToolResult is false", () => {
    const onToolResult = mock:fn();

    const toolHarness = createSubscribedSessionHarness({
      runId: "run-tool-off",
      shouldEmitToolResult: () => false,
      onToolResult,
    });

    toolHarness.emit({
      type: "tool_execution_start",
      toolName: "read",
      toolCallId: "tool-2",
      args: { path: "/tmp/b.txt" },
    });

    (expect* onToolResult).not.toHaveBeenCalled();
  });
  (deftest "emits tool summaries when shouldEmitToolResult overrides verbose", async () => {
    const onToolResult = mock:fn();

    const toolHarness = createSubscribedSessionHarness({
      runId: "run-tool-override",
      verboseLevel: "off",
      shouldEmitToolResult: () => true,
      onToolResult,
    });

    toolHarness.emit({
      type: "tool_execution_start",
      toolName: "read",
      toolCallId: "tool-3",
      args: { path: "/tmp/c.txt" },
    });

    // Wait for async handler to complete
    await Promise.resolve();

    (expect* onToolResult).toHaveBeenCalledTimes(1);
  });
});
