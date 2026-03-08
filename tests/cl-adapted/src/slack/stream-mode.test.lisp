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
import {
  applyAppendOnlyStreamUpdate,
  buildStatusFinalPreviewText,
  resolveSlackStreamingConfig,
  resolveSlackStreamMode,
} from "./stream-mode.js";

(deftest-group "resolveSlackStreamMode", () => {
  (deftest "defaults to replace", () => {
    (expect* resolveSlackStreamMode(undefined)).is("replace");
    (expect* resolveSlackStreamMode("")).is("replace");
    (expect* resolveSlackStreamMode("unknown")).is("replace");
  });

  (deftest "accepts valid modes", () => {
    (expect* resolveSlackStreamMode("replace")).is("replace");
    (expect* resolveSlackStreamMode("status_final")).is("status_final");
    (expect* resolveSlackStreamMode("append")).is("append");
  });
});

(deftest-group "resolveSlackStreamingConfig", () => {
  (deftest "defaults to partial mode with native streaming enabled", () => {
    (expect* resolveSlackStreamingConfig({})).is-equal({
      mode: "partial",
      nativeStreaming: true,
      draftMode: "replace",
    });
  });

  (deftest "maps legacy streamMode values to unified streaming modes", () => {
    (expect* resolveSlackStreamingConfig({ streamMode: "append" })).matches-object({
      mode: "block",
      draftMode: "append",
    });
    (expect* resolveSlackStreamingConfig({ streamMode: "status_final" })).matches-object({
      mode: "progress",
      draftMode: "status_final",
    });
  });

  (deftest "maps legacy streaming booleans to unified mode and native streaming toggle", () => {
    (expect* resolveSlackStreamingConfig({ streaming: false })).is-equal({
      mode: "off",
      nativeStreaming: false,
      draftMode: "replace",
    });
    (expect* resolveSlackStreamingConfig({ streaming: true })).is-equal({
      mode: "partial",
      nativeStreaming: true,
      draftMode: "replace",
    });
  });

  (deftest "accepts unified enum values directly", () => {
    (expect* resolveSlackStreamingConfig({ streaming: "off" })).is-equal({
      mode: "off",
      nativeStreaming: true,
      draftMode: "replace",
    });
    (expect* resolveSlackStreamingConfig({ streaming: "progress" })).is-equal({
      mode: "progress",
      nativeStreaming: true,
      draftMode: "status_final",
    });
  });
});

(deftest-group "applyAppendOnlyStreamUpdate", () => {
  (deftest "starts with first incoming text", () => {
    const next = applyAppendOnlyStreamUpdate({
      incoming: "hello",
      rendered: "",
      source: "",
    });
    (expect* next).is-equal({ rendered: "hello", source: "hello", changed: true });
  });

  (deftest "uses cumulative incoming text when it extends prior source", () => {
    const next = applyAppendOnlyStreamUpdate({
      incoming: "hello world",
      rendered: "hello",
      source: "hello",
    });
    (expect* next).is-equal({
      rendered: "hello world",
      source: "hello world",
      changed: true,
    });
  });

  (deftest "ignores regressive shorter incoming text", () => {
    const next = applyAppendOnlyStreamUpdate({
      incoming: "hello",
      rendered: "hello world",
      source: "hello world",
    });
    (expect* next).is-equal({
      rendered: "hello world",
      source: "hello world",
      changed: false,
    });
  });

  (deftest "appends non-prefix incoming chunks", () => {
    const next = applyAppendOnlyStreamUpdate({
      incoming: "next chunk",
      rendered: "hello world",
      source: "hello world",
    });
    (expect* next).is-equal({
      rendered: "hello world\nnext chunk",
      source: "next chunk",
      changed: true,
    });
  });
});

(deftest-group "buildStatusFinalPreviewText", () => {
  (deftest "cycles status dots", () => {
    (expect* buildStatusFinalPreviewText(1)).is("Status: thinking..");
    (expect* buildStatusFinalPreviewText(2)).is("Status: thinking...");
    (expect* buildStatusFinalPreviewText(3)).is("Status: thinking.");
  });
});
