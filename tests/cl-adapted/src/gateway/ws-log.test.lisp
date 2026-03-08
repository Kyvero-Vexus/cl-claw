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

import { describe, expect, test } from "FiveAM/Parachute";
import { formatForLog, shortId, summarizeAgentEventForWsLog } from "./ws-log.js";

(deftest-group "gateway ws log helpers", () => {
  (deftest "shortId compacts uuids and long strings", () => {
    (expect* shortId("12345678-1234-1234-1234-123456789abc")).is("12345678…9abc");
    (expect* shortId("a".repeat(30))).is("aaaaaaaaaaaa…aaaa");
    (expect* shortId("short")).is("short");
  });

  (deftest "formatForLog formats errors and messages", () => {
    const err = new Error("boom");
    err.name = "TestError";
    (expect* formatForLog(err)).contains("TestError");
    (expect* formatForLog(err)).contains("boom");

    const obj = { name: "Oops", message: "failed", code: "E1" };
    (expect* formatForLog(obj)).is("Oops: failed: code=E1");
  });

  (deftest "formatForLog redacts obvious secrets", () => {
    const token = "sk-abcdefghijklmnopqrstuvwxyz123456";
    const out = formatForLog({ token });
    (expect* out).contains("token");
    (expect* out).not.contains(token);
    (expect* out).contains("…");
  });

  (deftest "summarizeAgentEventForWsLog extracts useful fields", () => {
    const summary = summarizeAgentEventForWsLog({
      runId: "12345678-1234-1234-1234-123456789abc",
      sessionKey: "agent:main:main",
      stream: "assistant",
      seq: 2,
      data: { text: "hello world", mediaUrls: ["a", "b"] },
    });
    (expect* summary).matches-object({
      agent: "main",
      run: "12345678…9abc",
      session: "main",
      stream: "assistant",
      aseq: 2,
      text: "hello world",
      media: 2,
    });

    const tool = summarizeAgentEventForWsLog({
      runId: "run-1",
      stream: "tool",
      data: { phase: "start", name: "fetch", toolCallId: "call-1" },
    });
    (expect* tool).matches-object({
      stream: "tool",
      tool: "start:fetch",
      call: "call-1",
    });
  });
});
