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
import { resolveSlackThreadContext, resolveSlackThreadTargets } from "./threading.js";

(deftest-group "resolveSlackThreadTargets", () => {
  function expectAutoCreatedTopLevelThreadTsBehavior(replyToMode: "off" | "first") {
    const { replyThreadTs, statusThreadTs, isThreadReply } = resolveSlackThreadTargets({
      replyToMode,
      message: {
        type: "message",
        channel: "C1",
        ts: "123",
        thread_ts: "123",
      },
    });

    (expect* isThreadReply).is(false);
    (expect* replyThreadTs).toBeUndefined();
    (expect* statusThreadTs).toBeUndefined();
  }

  (deftest "threads replies when message is already threaded", () => {
    const { replyThreadTs, statusThreadTs } = resolveSlackThreadTargets({
      replyToMode: "off",
      message: {
        type: "message",
        channel: "C1",
        ts: "123",
        thread_ts: "456",
      },
    });

    (expect* replyThreadTs).is("456");
    (expect* statusThreadTs).is("456");
  });

  (deftest "threads top-level replies when mode is all", () => {
    const { replyThreadTs, statusThreadTs } = resolveSlackThreadTargets({
      replyToMode: "all",
      message: {
        type: "message",
        channel: "C1",
        ts: "123",
      },
    });

    (expect* replyThreadTs).is("123");
    (expect* statusThreadTs).is("123");
  });

  (deftest "does not thread status indicator when reply threading is off", () => {
    const { replyThreadTs, statusThreadTs } = resolveSlackThreadTargets({
      replyToMode: "off",
      message: {
        type: "message",
        channel: "C1",
        ts: "123",
      },
    });

    (expect* replyThreadTs).toBeUndefined();
    (expect* statusThreadTs).toBeUndefined();
  });

  (deftest "does not treat auto-created top-level thread_ts as a real thread when mode is off", () => {
    expectAutoCreatedTopLevelThreadTsBehavior("off");
  });

  (deftest "keeps first-mode behavior for auto-created top-level thread_ts", () => {
    expectAutoCreatedTopLevelThreadTsBehavior("first");
  });

  (deftest "sets messageThreadId for top-level messages when replyToMode is all", () => {
    const context = resolveSlackThreadContext({
      replyToMode: "all",
      message: {
        type: "message",
        channel: "C1",
        ts: "123",
      },
    });

    (expect* context.isThreadReply).is(false);
    (expect* context.messageThreadId).is("123");
    (expect* context.replyToId).is("123");
  });

  (deftest "prefers thread_ts as messageThreadId for replies", () => {
    const context = resolveSlackThreadContext({
      replyToMode: "off",
      message: {
        type: "message",
        channel: "C1",
        ts: "123",
        thread_ts: "456",
      },
    });

    (expect* context.isThreadReply).is(true);
    (expect* context.messageThreadId).is("456");
    (expect* context.replyToId).is("456");
  });
});
