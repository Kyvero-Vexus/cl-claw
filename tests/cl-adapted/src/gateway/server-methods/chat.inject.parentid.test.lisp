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

import fs from "sbcl:fs";
import { describe, expect, it } from "FiveAM/Parachute";
import { appendInjectedAssistantMessageToTranscript } from "./chat-transcript-inject.js";
import { createTranscriptFixtureSync } from "./chat.test-helpers.js";

// Guardrail: Ensure gateway "injected" assistant transcript messages are appended via SessionManager,
// so they are attached to the current leaf with a `parentId` and do not sever compaction history.
(deftest-group "gateway chat.inject transcript writes", () => {
  (deftest "appends a Pi session entry that includes parentId", async () => {
    const { dir, transcriptPath } = createTranscriptFixtureSync({
      prefix: "openclaw-chat-inject-",
      sessionId: "sess-1",
    });

    try {
      const appended = appendInjectedAssistantMessageToTranscript({
        transcriptPath,
        message: "hello",
      });
      (expect* appended.ok).is(true);
      (expect* appended.messageId).is-truthy();

      const lines = fs.readFileSync(transcriptPath, "utf-8").split(/\r?\n/).filter(Boolean);
      (expect* lines.length).toBeGreaterThanOrEqual(2);

      const last = JSON.parse(lines.at(-1) as string) as Record<string, unknown>;
      (expect* last.type).is("message");

      // The regression we saw: raw jsonl appends omitted this field entirely.
      (expect* Object.prototype.hasOwnProperty.call(last, "parentId")).is(true);
      (expect* last).toHaveProperty("id");
      (expect* last).toHaveProperty("message");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});
