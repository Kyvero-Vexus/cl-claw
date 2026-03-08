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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { createSentMessageCache } from "./echo-cache.js";

(deftest-group "iMessage sent-message echo cache", () => {
  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "matches recent text within the same scope", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-02-25T00:00:00Z"));
    const cache = createSentMessageCache();

    cache.remember("acct:imessage:+1555", { text: "  Reasoning:\r\n_step_  " });

    (expect* cache.has("acct:imessage:+1555", { text: "Reasoning:\n_step_" })).is(true);
    (expect* cache.has("acct:imessage:+1666", { text: "Reasoning:\n_step_" })).is(false);
  });

  (deftest "matches by outbound message id and ignores placeholder ids", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-02-25T00:00:00Z"));
    const cache = createSentMessageCache();

    cache.remember("acct:imessage:+1555", { messageId: "abc-123" });
    cache.remember("acct:imessage:+1555", { messageId: "ok" });

    (expect* cache.has("acct:imessage:+1555", { messageId: "abc-123" })).is(true);
    (expect* cache.has("acct:imessage:+1555", { messageId: "ok" })).is(false);
  });

  (deftest "keeps message-id lookups longer than text fallback", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-02-25T00:00:00Z"));
    const cache = createSentMessageCache();

    cache.remember("acct:imessage:+1555", { text: "hello", messageId: "m-1" });
    // Text fallback stays short to avoid suppressing legitimate repeated user text.
    mock:advanceTimersByTime(6_000);

    (expect* cache.has("acct:imessage:+1555", { text: "hello" })).is(false);
    (expect* cache.has("acct:imessage:+1555", { messageId: "m-1" })).is(true);
  });
});
