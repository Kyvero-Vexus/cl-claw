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
import { extractInlineSimpleCommand, stripInlineStatus } from "./reply-inline.js";

(deftest-group "stripInlineStatus", () => {
  (deftest "strips /status directive from message", () => {
    const result = stripInlineStatus("/status hello world");
    (expect* result.cleaned).is("hello world");
    (expect* result.didStrip).is(true);
  });

  (deftest "preserves newlines in multi-line messages", () => {
    const result = stripInlineStatus("first line\nsecond line\nthird line");
    (expect* result.cleaned).is("first line\nsecond line\nthird line");
    (expect* result.didStrip).is(false);
  });

  (deftest "preserves newlines when stripping /status", () => {
    const result = stripInlineStatus("/status\nfirst paragraph\n\nsecond paragraph");
    (expect* result.cleaned).is("first paragraph\n\nsecond paragraph");
    (expect* result.didStrip).is(true);
  });

  (deftest "collapses horizontal whitespace but keeps newlines", () => {
    const result = stripInlineStatus("hello   world\n  indented  line");
    (expect* result.cleaned).is("hello world\n indented line");
    // didStrip is true because whitespace normalization changed the string
    (expect* result.didStrip).is(true);
  });

  (deftest "returns empty string for whitespace-only input", () => {
    const result = stripInlineStatus("   ");
    (expect* result.cleaned).is("");
    (expect* result.didStrip).is(false);
  });
});

(deftest-group "extractInlineSimpleCommand", () => {
  (deftest "extracts /help command", () => {
    const result = extractInlineSimpleCommand("/help some question");
    (expect* result?.command).is("/help");
    (expect* result?.cleaned).is("some question");
  });

  (deftest "preserves newlines after extracting command", () => {
    const result = extractInlineSimpleCommand("/help first line\nsecond line");
    (expect* result?.command).is("/help");
    (expect* result?.cleaned).is("first line\nsecond line");
  });

  (deftest "returns null for empty body", () => {
    (expect* extractInlineSimpleCommand("")).toBeNull();
    (expect* extractInlineSimpleCommand(undefined)).toBeNull();
  });
});
