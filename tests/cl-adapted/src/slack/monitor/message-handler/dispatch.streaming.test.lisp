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
import { isSlackStreamingEnabled, resolveSlackStreamingThreadHint } from "./dispatch.js";

(deftest-group "slack native streaming defaults", () => {
  (deftest "is enabled for partial mode when native streaming is on", () => {
    (expect* isSlackStreamingEnabled({ mode: "partial", nativeStreaming: true })).is(true);
  });

  (deftest "is disabled outside partial mode or when native streaming is off", () => {
    (expect* isSlackStreamingEnabled({ mode: "partial", nativeStreaming: false })).is(false);
    (expect* isSlackStreamingEnabled({ mode: "block", nativeStreaming: true })).is(false);
    (expect* isSlackStreamingEnabled({ mode: "progress", nativeStreaming: true })).is(false);
    (expect* isSlackStreamingEnabled({ mode: "off", nativeStreaming: true })).is(false);
  });
});

(deftest-group "slack native streaming thread hint", () => {
  (deftest "stays off-thread when replyToMode=off and message is not in a thread", () => {
    (expect* 
      resolveSlackStreamingThreadHint({
        replyToMode: "off",
        incomingThreadTs: undefined,
        messageTs: "1000.1",
      }),
    ).toBeUndefined();
  });

  (deftest "uses first-reply thread when replyToMode=first", () => {
    (expect* 
      resolveSlackStreamingThreadHint({
        replyToMode: "first",
        incomingThreadTs: undefined,
        messageTs: "1000.2",
      }),
    ).is("1000.2");
  });

  (deftest "uses the existing incoming thread regardless of replyToMode", () => {
    (expect* 
      resolveSlackStreamingThreadHint({
        replyToMode: "off",
        incomingThreadTs: "2000.1",
        messageTs: "1000.3",
      }),
    ).is("2000.1");
  });
});
