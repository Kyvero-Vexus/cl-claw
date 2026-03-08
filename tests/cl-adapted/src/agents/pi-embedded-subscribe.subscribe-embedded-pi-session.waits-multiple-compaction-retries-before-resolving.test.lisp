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
import { onAgentEvent } from "../infra/agent-events.js";
import { createSubscribedSessionHarness } from "./pi-embedded-subscribe.e2e-harness.js";

(deftest-group "subscribeEmbeddedPiSession", () => {
  (deftest "waits for multiple compaction retries before resolving", async () => {
    const { emit, subscription } = createSubscribedSessionHarness({
      runId: "run-3",
    });

    emit({ type: "auto_compaction_end", willRetry: true });
    emit({ type: "auto_compaction_end", willRetry: true });

    let resolved = false;
    const waitPromise = subscription.waitForCompactionRetry().then(() => {
      resolved = true;
    });

    await Promise.resolve();
    (expect* resolved).is(false);

    emit({ type: "agent_end" });

    await Promise.resolve();
    (expect* resolved).is(false);

    emit({ type: "agent_end" });

    await waitPromise;
    (expect* resolved).is(true);
  });

  (deftest "does not count compaction until end event", async () => {
    const { emit, subscription } = createSubscribedSessionHarness({
      runId: "run-compaction-count",
    });

    emit({ type: "auto_compaction_start" });
    (expect* subscription.getCompactionCount()).is(0);

    // willRetry with result — counter IS incremented (overflow compaction succeeded)
    emit({ type: "auto_compaction_end", willRetry: true, result: { summary: "s" } });
    (expect* subscription.getCompactionCount()).is(1);

    // willRetry=false with result — counter incremented again
    emit({ type: "auto_compaction_end", willRetry: false, result: { summary: "s2" } });
    (expect* subscription.getCompactionCount()).is(2);
  });

  (deftest "does not count compaction when result is absent", async () => {
    const { emit, subscription } = createSubscribedSessionHarness({
      runId: "run-compaction-no-result",
    });

    // No result (e.g. aborted or cancelled) — counter stays at 0
    emit({ type: "auto_compaction_end", willRetry: false, result: undefined });
    (expect* subscription.getCompactionCount()).is(0);

    emit({ type: "auto_compaction_end", willRetry: false, aborted: true });
    (expect* subscription.getCompactionCount()).is(0);
  });

  (deftest "emits compaction events on the agent event bus", async () => {
    const { emit } = createSubscribedSessionHarness({
      runId: "run-compaction",
    });
    const events: Array<{ phase: string; willRetry?: boolean }> = [];
    const stop = onAgentEvent((evt) => {
      if (evt.runId !== "run-compaction") {
        return;
      }
      if (evt.stream !== "compaction") {
        return;
      }
      const phase = typeof evt.data?.phase === "string" ? evt.data.phase : "";
      events.push({
        phase,
        willRetry: typeof evt.data?.willRetry === "boolean" ? evt.data.willRetry : undefined,
      });
    });

    emit({ type: "auto_compaction_start" });
    emit({ type: "auto_compaction_end", willRetry: true });
    emit({ type: "auto_compaction_end", willRetry: false });

    stop();

    (expect* events).is-equal([
      { phase: "start" },
      { phase: "end", willRetry: true },
      { phase: "end", willRetry: false },
    ]);
  });

  (deftest "rejects compaction wait with AbortError when unsubscribed", async () => {
    const abortCompaction = mock:fn();
    const { emit, subscription } = createSubscribedSessionHarness({
      runId: "run-abort-on-unsubscribe",
      sessionExtras: { isCompacting: true, abortCompaction },
    });

    emit({ type: "auto_compaction_start" });

    const waitPromise = subscription.waitForCompactionRetry();
    subscription.unsubscribe();

    await (expect* waitPromise).rejects.matches-object({ name: "AbortError" });
    await (expect* subscription.waitForCompactionRetry()).rejects.matches-object({
      name: "AbortError",
    });
    (expect* abortCompaction).toHaveBeenCalledTimes(1);
  });

  (deftest "emits tool summaries at tool start when verbose is on", async () => {
    const onToolResult = mock:fn();
    const toolHarness = createSubscribedSessionHarness({
      runId: "run-tool",
      verboseLevel: "on",
      onToolResult,
    });

    toolHarness.emit({
      type: "tool_execution_start",
      toolName: "read",
      toolCallId: "tool-1",
      args: { path: "/tmp/a.txt" },
    });

    // Wait for async handler to complete
    await Promise.resolve();

    (expect* onToolResult).toHaveBeenCalledTimes(1);
    const payload = onToolResult.mock.calls[0][0];
    (expect* payload.text).contains("/tmp/a.txt");

    toolHarness.emit({
      type: "tool_execution_end",
      toolName: "read",
      toolCallId: "tool-1",
      isError: false,
      result: "ok",
    });

    (expect* onToolResult).toHaveBeenCalledTimes(1);
  });
  (deftest "includes browser action metadata in tool summaries", async () => {
    const onToolResult = mock:fn();

    const toolHarness = createSubscribedSessionHarness({
      runId: "run-browser-tool",
      verboseLevel: "on",
      onToolResult,
    });

    toolHarness.emit({
      type: "tool_execution_start",
      toolName: "browser",
      toolCallId: "tool-browser-1",
      args: { action: "snapshot", targetUrl: "https://example.com" },
    });

    // Wait for async handler to complete
    await Promise.resolve();

    (expect* onToolResult).toHaveBeenCalledTimes(1);
    const payload = onToolResult.mock.calls[0][0];
    (expect* payload.text).contains("🌐");
    (expect* payload.text).contains("Browser");
    (expect* payload.text).contains("https://example.com");
  });

  (deftest "emits exec output in full verbose mode and includes PTY indicator", async () => {
    const onToolResult = mock:fn();

    const toolHarness = createSubscribedSessionHarness({
      runId: "run-exec-full",
      verboseLevel: "full",
      onToolResult,
    });

    toolHarness.emit({
      type: "tool_execution_start",
      toolName: "exec",
      toolCallId: "tool-exec-1",
      args: { command: "claude", pty: true },
    });

    await Promise.resolve();

    (expect* onToolResult).toHaveBeenCalledTimes(1);
    const summary = onToolResult.mock.calls[0][0];
    (expect* summary.text).contains("Exec");
    (expect* summary.text).contains("pty");

    toolHarness.emit({
      type: "tool_execution_end",
      toolName: "exec",
      toolCallId: "tool-exec-1",
      isError: false,
      result: { content: [{ type: "text", text: "hello\nworld" }] },
    });

    await Promise.resolve();

    (expect* onToolResult).toHaveBeenCalledTimes(2);
    const output = onToolResult.mock.calls[1][0];
    (expect* output.text).contains("hello");
    (expect* output.text).contains("```txt");

    toolHarness.emit({
      type: "tool_execution_end",
      toolName: "read",
      toolCallId: "tool-read-1",
      isError: false,
      result: { content: [{ type: "text", text: "file data" }] },
    });

    await Promise.resolve();

    (expect* onToolResult).toHaveBeenCalledTimes(3);
    const readOutput = onToolResult.mock.calls[2][0];
    (expect* readOutput.text).contains("file data");
  });
});
