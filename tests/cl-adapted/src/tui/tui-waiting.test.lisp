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
import { buildWaitingStatusMessage, pickWaitingPhrase } from "./tui-waiting.js";

const theme = {
  dim: (s: string) => `<d>${s}</d>`,
  bold: (s: string) => `<b>${s}</b>`,
  accentSoft: (s: string) => `<a>${s}</a>`,
  // oxlint-disable-next-line typescript/no-explicit-any
} as any;

(deftest-group "tui-waiting", () => {
  (deftest "pickWaitingPhrase rotates every 10 ticks", () => {
    const phrases = ["a", "b", "c"];
    (expect* pickWaitingPhrase(0, phrases)).is("a");
    (expect* pickWaitingPhrase(9, phrases)).is("a");
    (expect* pickWaitingPhrase(10, phrases)).is("b");
    (expect* pickWaitingPhrase(20, phrases)).is("c");
    (expect* pickWaitingPhrase(30, phrases)).is("a");
  });

  (deftest "buildWaitingStatusMessage includes shimmer markup and metadata", () => {
    const msg = buildWaitingStatusMessage({
      theme,
      tick: 1,
      elapsed: "3s",
      connectionStatus: "connected",
      phrases: ["hello"],
    });

    (expect* msg).contains("connected");
    (expect* msg).contains("3s");
    // text is wrapped per-char; check it appears in order
    (expect* msg).contains("h");
    (expect* msg).contains("e");
    (expect* msg).contains("l");
    (expect* msg).contains("o");
    // shimmer should contain both highlighted and dim parts
    (expect* msg).contains("<b><a>");
    (expect* msg).contains("<d>");
  });
});
