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
import type { SlackMessageEvent } from "../types.js";
import { buildSlackDebounceKey } from "./message-handler.js";

function makeMessage(overrides: Partial<SlackMessageEvent> = {}): SlackMessageEvent {
  return {
    type: "message",
    channel: "C123",
    user: "U456",
    ts: "1709000000.000100",
    text: "hello",
    ...overrides,
  } as SlackMessageEvent;
}

(deftest-group "buildSlackDebounceKey", () => {
  const accountId = "default";

  (deftest "returns null when message has no sender", () => {
    const msg = makeMessage({ user: undefined, bot_id: undefined });
    (expect* buildSlackDebounceKey(msg, accountId)).toBeNull();
  });

  (deftest "scopes thread replies by thread_ts", () => {
    const msg = makeMessage({ thread_ts: "1709000000.000001" });
    (expect* buildSlackDebounceKey(msg, accountId)).is("slack:default:C123:1709000000.000001:U456");
  });

  (deftest "isolates unresolved thread replies with maybe-thread prefix", () => {
    const msg = makeMessage({
      parent_user_id: "U789",
      thread_ts: undefined,
      ts: "1709000000.000200",
    });
    (expect* buildSlackDebounceKey(msg, accountId)).is(
      "slack:default:C123:maybe-thread:1709000000.000200:U456",
    );
  });

  (deftest "scopes top-level messages by their own timestamp to prevent cross-thread collisions", () => {
    const msgA = makeMessage({ ts: "1709000000.000100" });
    const msgB = makeMessage({ ts: "1709000000.000200" });

    const keyA = buildSlackDebounceKey(msgA, accountId);
    const keyB = buildSlackDebounceKey(msgB, accountId);

    // Different timestamps => different debounce keys
    (expect* keyA).not.is(keyB);
    (expect* keyA).is("slack:default:C123:1709000000.000100:U456");
    (expect* keyB).is("slack:default:C123:1709000000.000200:U456");
  });

  (deftest "keeps top-level DMs channel-scoped to preserve short-message batching", () => {
    const dmA = makeMessage({ channel: "D123", ts: "1709000000.000100" });
    const dmB = makeMessage({ channel: "D123", ts: "1709000000.000200" });
    (expect* buildSlackDebounceKey(dmA, accountId)).is("slack:default:D123:U456");
    (expect* buildSlackDebounceKey(dmB, accountId)).is("slack:default:D123:U456");
  });

  (deftest "falls back to bare channel when no timestamp is available", () => {
    const msg = makeMessage({ ts: undefined, event_ts: undefined });
    (expect* buildSlackDebounceKey(msg, accountId)).is("slack:default:C123:U456");
  });

  (deftest "uses bot_id as sender fallback", () => {
    const msg = makeMessage({ user: undefined, bot_id: "B999" });
    (expect* buildSlackDebounceKey(msg, accountId)).is("slack:default:C123:1709000000.000100:B999");
  });
});
