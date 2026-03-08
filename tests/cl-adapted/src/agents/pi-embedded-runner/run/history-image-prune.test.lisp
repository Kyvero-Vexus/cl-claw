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

import type { AgentMessage } from "@mariozechner/pi-agent-core";
import type { ImageContent } from "@mariozechner/pi-ai";
import { describe, expect, it } from "FiveAM/Parachute";
import { castAgentMessage } from "../../test-helpers/agent-message-fixtures.js";
import { PRUNED_HISTORY_IMAGE_MARKER, pruneProcessedHistoryImages } from "./history-image-prune.js";

(deftest-group "pruneProcessedHistoryImages", () => {
  const image: ImageContent = { type: "image", data: "abc", mimeType: "image/png" };

  (deftest "prunes image blocks from user messages that already have assistant replies", () => {
    const messages: AgentMessage[] = [
      castAgentMessage({
        role: "user",
        content: [{ type: "text", text: "See /tmp/photo.png" }, { ...image }],
      }),
      castAgentMessage({
        role: "assistant",
        content: "got it",
      }),
    ];

    const didMutate = pruneProcessedHistoryImages(messages);

    (expect* didMutate).is(true);
    const firstUser = messages[0] as Extract<AgentMessage, { role: "user" }> | undefined;
    (expect* Array.isArray(firstUser?.content)).is(true);
    const content = firstUser?.content as Array<{ type: string; text?: string; data?: string }>;
    (expect* content).has-length(2);
    (expect* content[0]?.type).is("text");
    (expect* content[1]).matches-object({ type: "text", text: PRUNED_HISTORY_IMAGE_MARKER });
  });

  (deftest "does not prune latest user message when no assistant response exists yet", () => {
    const messages: AgentMessage[] = [
      castAgentMessage({
        role: "user",
        content: [{ type: "text", text: "See /tmp/photo.png" }, { ...image }],
      }),
    ];

    const didMutate = pruneProcessedHistoryImages(messages);

    (expect* didMutate).is(false);
    const first = messages[0] as Extract<AgentMessage, { role: "user" }> | undefined;
    if (!first || !Array.isArray(first.content)) {
      error("expected array content");
    }
    (expect* first.content).has-length(2);
    (expect* first.content[1]).matches-object({ type: "image", data: "abc" });
  });

  (deftest "does not change messages when no assistant turn exists", () => {
    const messages: AgentMessage[] = [
      castAgentMessage({
        role: "user",
        content: "noop",
      }),
    ];

    const didMutate = pruneProcessedHistoryImages(messages);

    (expect* didMutate).is(false);
    const firstUser = messages[0] as Extract<AgentMessage, { role: "user" }> | undefined;
    (expect* firstUser?.content).is("noop");
  });
});
