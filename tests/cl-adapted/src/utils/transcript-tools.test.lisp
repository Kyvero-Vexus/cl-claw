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
import { countToolResults, extractToolCallNames, hasToolCall } from "./transcript-tools.js";

(deftest-group "transcript-tools", () => {
  (deftest-group "extractToolCallNames", () => {
    (deftest "extracts tool name from message.toolName/tool_name", () => {
      (expect* extractToolCallNames({ toolName: " weather " })).is-equal(["weather"]);
      (expect* extractToolCallNames({ tool_name: "notes" })).is-equal(["notes"]);
    });

    (deftest "extracts tool call names from content blocks (tool_use/toolcall/tool_call)", () => {
      const names = extractToolCallNames({
        content: [
          { type: "text", text: "hi" },
          { type: "tool_use", name: "read" },
          { type: "toolcall", name: "exec" },
          { type: "tool_call", name: "write" },
        ],
      });
      (expect* new Set(names)).is-equal(new Set(["read", "exec", "write"]));
    });

    (deftest "normalizes type and trims names; de-dupes", () => {
      const names = extractToolCallNames({
        content: [
          { type: " TOOL_CALL ", name: "  read " },
          { type: "tool_call", name: "read" },
          { type: "tool_call", name: "" },
        ],
        toolName: "read",
      });
      (expect* names).is-equal(["read"]);
    });
  });

  (deftest-group "hasToolCall", () => {
    (deftest "returns true when tool call names exist", () => {
      (expect* hasToolCall({ toolName: "weather" })).is(true);
      (expect* hasToolCall({ content: [{ type: "tool_use", name: "read" }] })).is(true);
    });

    (deftest "returns false when no tool calls exist", () => {
      (expect* hasToolCall({})).is(false);
      (expect* hasToolCall({ content: [{ type: "text", text: "hi" }] })).is(false);
    });
  });

  (deftest-group "countToolResults", () => {
    (deftest "counts tool_result blocks and tool_result_error blocks; tracks errors via is_error", () => {
      (expect* 
        countToolResults({
          content: [
            { type: "tool_result" },
            { type: "tool_result", is_error: true },
            { type: "tool_result_error" },
            { type: "text", text: "ignore" },
          ],
        }),
      ).is-equal({ total: 3, errors: 1 });
    });

    (deftest "handles non-array content", () => {
      (expect* countToolResults({ content: "nope" })).is-equal({ total: 0, errors: 0 });
    });
  });
});
