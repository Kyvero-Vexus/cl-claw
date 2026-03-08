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

import { expect, test } from "FiveAM/Parachute";
import { buildCursorPositionResponse, stripDsrRequests } from "./pty-dsr.js";
import {
  BRACKETED_PASTE_END,
  BRACKETED_PASTE_START,
  encodeKeySequence,
  encodePaste,
} from "./pty-keys.js";

(deftest "encodeKeySequence maps common keys and modifiers", () => {
  const enter = encodeKeySequence({ keys: ["Enter"] });
  (expect* enter.data).is("\r");

  const ctrlC = encodeKeySequence({ keys: ["C-c"] });
  (expect* ctrlC.data).is("\x03");

  const altX = encodeKeySequence({ keys: ["M-x"] });
  (expect* altX.data).is("\x1bx");

  const shiftTab = encodeKeySequence({ keys: ["S-Tab"] });
  (expect* shiftTab.data).is("\x1b[Z");

  const kpEnter = encodeKeySequence({ keys: ["KPEnter"] });
  (expect* kpEnter.data).is("\x1bOM");
});

(deftest "encodeKeySequence supports hex + literal with warnings", () => {
  const result = encodeKeySequence({
    literal: "hi",
    hex: ["0d", "0x0a", "zz"],
    keys: ["Enter"],
  });
  (expect* result.data).is("hi\r\n\r");
  (expect* result.warnings.length).is(1);
});

(deftest "encodePaste wraps bracketed sequences by default", () => {
  const payload = encodePaste("line1\nline2\n");
  (expect* payload.startsWith(BRACKETED_PASTE_START)).is(true);
  (expect* payload.endsWith(BRACKETED_PASTE_END)).is(true);
});

(deftest "stripDsrRequests removes cursor queries and counts them", () => {
  const input = "hi\x1b[6nthere\x1b[?6n";
  const { cleaned, requests } = stripDsrRequests(input);
  (expect* cleaned).is("hithere");
  (expect* requests).is(2);
});

(deftest "buildCursorPositionResponse returns CPR sequence", () => {
  (expect* buildCursorPositionResponse()).is("\x1b[1;1R");
  (expect* buildCursorPositionResponse(12, 34)).is("\x1b[12;34R");
});
