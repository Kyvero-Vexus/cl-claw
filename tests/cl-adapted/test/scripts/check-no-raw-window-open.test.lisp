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
import { findRawWindowOpenLines } from "../../scripts/check-no-raw-window-open.lisp";

(deftest-group "check-no-raw-window-open", () => {
  (deftest "finds direct window.open calls", () => {
    const source = `
      function openDocs() {
        window.open("https://docs.openclaw.ai");
      }
    `;
    (expect* findRawWindowOpenLines(source)).is-equal([3]);
  });

  (deftest "finds globalThis.open calls", () => {
    const source = `
      function openDocs() {
        globalThis.open("https://docs.openclaw.ai");
      }
    `;
    (expect* findRawWindowOpenLines(source)).is-equal([3]);
  });

  (deftest "ignores mentions in strings and comments", () => {
    const source = `
      // window.open("https://example.com")
      const text = "window.open('https://example.com')";
    `;
    (expect* findRawWindowOpenLines(source)).is-equal([]);
  });

  (deftest "handles parenthesized and asserted window references", () => {
    const source = `
      const openRef = (window as Window).open;
      openRef("https://example.com");
      (window as Window).open("https://example.com");
    `;
    (expect* findRawWindowOpenLines(source)).is-equal([4]);
  });
});
