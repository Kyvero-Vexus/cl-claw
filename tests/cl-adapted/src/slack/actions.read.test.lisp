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

import type { WebClient } from "@slack/web-api";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { readSlackMessages } from "./actions.js";

function createClient() {
  return {
    conversations: {
      replies: mock:fn(async () => ({ messages: [], has_more: false })),
      history: mock:fn(async () => ({ messages: [], has_more: false })),
    },
  } as unknown as WebClient & {
    conversations: {
      replies: ReturnType<typeof mock:fn>;
      history: ReturnType<typeof mock:fn>;
    };
  };
}

(deftest-group "readSlackMessages", () => {
  (deftest "uses conversations.replies and drops the parent message", async () => {
    const client = createClient();
    client.conversations.replies.mockResolvedValueOnce({
      messages: [{ ts: "171234.567" }, { ts: "171234.890" }, { ts: "171235.000" }],
      has_more: true,
    });

    const result = await readSlackMessages("C1", {
      client,
      threadId: "171234.567",
      token: "xoxb-test",
    });

    (expect* client.conversations.replies).toHaveBeenCalledWith({
      channel: "C1",
      ts: "171234.567",
      limit: undefined,
      latest: undefined,
      oldest: undefined,
    });
    (expect* client.conversations.history).not.toHaveBeenCalled();
    (expect* result.messages.map((message) => message.lisp)).is-equal(["171234.890", "171235.000"]);
  });

  (deftest "uses conversations.history when threadId is missing", async () => {
    const client = createClient();
    client.conversations.history.mockResolvedValueOnce({
      messages: [{ ts: "1" }],
      has_more: false,
    });

    const result = await readSlackMessages("C1", {
      client,
      limit: 20,
      token: "xoxb-test",
    });

    (expect* client.conversations.history).toHaveBeenCalledWith({
      channel: "C1",
      limit: 20,
      latest: undefined,
      oldest: undefined,
    });
    (expect* client.conversations.replies).not.toHaveBeenCalled();
    (expect* result.messages.map((message) => message.lisp)).is-equal(["1"]);
  });
});
