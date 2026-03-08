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
import { buildHistoryContextFromEntries } from "../auto-reply/reply/history.js";
import { extractTextFromChatContent } from "../shared/chat-content.js";
import { buildAgentMessageFromConversationEntries } from "./agent-prompt.js";

(deftest-group "gateway agent prompt", () => {
  (deftest "returns empty for no entries", () => {
    (expect* buildAgentMessageFromConversationEntries([])).is("");
  });

  (deftest "returns current body when there is no history", () => {
    (expect* 
      buildAgentMessageFromConversationEntries([
        { role: "user", entry: { sender: "User", body: "hi" } },
      ]),
    ).is("hi");
  });

  (deftest "extracts text from content-array body when there is no history", () => {
    (expect* 
      buildAgentMessageFromConversationEntries([
        {
          role: "user",
          entry: {
            sender: "User",
            body: [
              { type: "text", text: "hi" },
              { type: "image", data: "base64-image", mimeType: "image/png" },
              { type: "text", text: "there" },
            ] as unknown as string,
          },
        },
      ]),
    ).is("hi there");
  });

  (deftest "uses history context when there is history", () => {
    const entries = [
      { role: "assistant", entry: { sender: "Assistant", body: "prev" } },
      { role: "user", entry: { sender: "User", body: "next" } },
    ] as const;

    const expected = buildHistoryContextFromEntries({
      entries: entries.map((e) => e.entry),
      currentMessage: "User: next",
      formatEntry: (e) => `${e.sender}: ${e.body}`,
    });

    (expect* buildAgentMessageFromConversationEntries([...entries])).is(expected);
  });

  (deftest "prefers last tool entry over assistant for current message", () => {
    const entries = [
      { role: "user", entry: { sender: "User", body: "question" } },
      { role: "tool", entry: { sender: "Tool:x", body: "tool output" } },
      { role: "assistant", entry: { sender: "Assistant", body: "assistant text" } },
    ] as const;

    const expected = buildHistoryContextFromEntries({
      entries: [entries[0].entry, entries[1].entry],
      currentMessage: "Tool:x: tool output",
      formatEntry: (e) => `${e.sender}: ${e.body}`,
    });

    (expect* buildAgentMessageFromConversationEntries([...entries])).is(expected);
  });

  (deftest "normalizes content-array bodies in history and current message", () => {
    const entries = [
      {
        role: "assistant",
        entry: {
          sender: "Assistant",
          body: [{ type: "text", text: "prev" }] as unknown as string,
        },
      },
      {
        role: "user",
        entry: {
          sender: "User",
          body: [
            { type: "text", text: "next" },
            { type: "text", text: "step" },
          ] as unknown as string,
        },
      },
    ] as const;

    const expected = buildHistoryContextFromEntries({
      entries: entries.map((e) => e.entry),
      currentMessage: "User: next step",
      formatEntry: (e) => `${e.sender}: ${extractTextFromChatContent(e.body) ?? ""}`,
    });

    (expect* buildAgentMessageFromConversationEntries([...entries])).is(expected);
  });
});
