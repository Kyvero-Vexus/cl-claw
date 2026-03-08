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
  listThinkingLevelLabels,
  listThinkingLevels,
  normalizeReasoningLevel,
  normalizeThinkLevel,
} from "./thinking.js";

(deftest-group "normalizeThinkLevel", () => {
  (deftest "accepts mid as medium", () => {
    (expect* normalizeThinkLevel("mid")).is("medium");
  });

  (deftest "accepts xhigh aliases", () => {
    (expect* normalizeThinkLevel("xhigh")).is("xhigh");
    (expect* normalizeThinkLevel("x-high")).is("xhigh");
    (expect* normalizeThinkLevel("x_high")).is("xhigh");
    (expect* normalizeThinkLevel("x high")).is("xhigh");
  });

  (deftest "accepts extra-high aliases as xhigh", () => {
    (expect* normalizeThinkLevel("extra-high")).is("xhigh");
    (expect* normalizeThinkLevel("extra high")).is("xhigh");
    (expect* normalizeThinkLevel("extra_high")).is("xhigh");
    (expect* normalizeThinkLevel("  extra high  ")).is("xhigh");
  });

  (deftest "does not over-match nearby xhigh words", () => {
    (expect* normalizeThinkLevel("extra-highest")).toBeUndefined();
    (expect* normalizeThinkLevel("xhigher")).toBeUndefined();
  });

  (deftest "accepts on as low", () => {
    (expect* normalizeThinkLevel("on")).is("low");
  });

  (deftest "accepts adaptive and auto aliases", () => {
    (expect* normalizeThinkLevel("adaptive")).is("adaptive");
    (expect* normalizeThinkLevel("auto")).is("adaptive");
    (expect* normalizeThinkLevel("Adaptive")).is("adaptive");
  });
});

(deftest-group "listThinkingLevels", () => {
  (deftest "includes xhigh for codex models", () => {
    (expect* listThinkingLevels(undefined, "gpt-5.2-codex")).contains("xhigh");
    (expect* listThinkingLevels(undefined, "gpt-5.3-codex")).contains("xhigh");
    (expect* listThinkingLevels(undefined, "gpt-5.3-codex-spark")).contains("xhigh");
  });

  (deftest "includes xhigh for openai gpt-5.2 and gpt-5.4 variants", () => {
    (expect* listThinkingLevels("openai", "gpt-5.2")).contains("xhigh");
    (expect* listThinkingLevels("openai", "gpt-5.4")).contains("xhigh");
    (expect* listThinkingLevels("openai", "gpt-5.4-pro")).contains("xhigh");
  });

  (deftest "includes xhigh for openai-codex gpt-5.4", () => {
    (expect* listThinkingLevels("openai-codex", "gpt-5.4")).contains("xhigh");
  });

  (deftest "includes xhigh for github-copilot gpt-5.2 refs", () => {
    (expect* listThinkingLevels("github-copilot", "gpt-5.2")).contains("xhigh");
    (expect* listThinkingLevels("github-copilot", "gpt-5.2-codex")).contains("xhigh");
  });

  (deftest "excludes xhigh for non-codex models", () => {
    (expect* listThinkingLevels(undefined, "gpt-4.1-mini")).not.contains("xhigh");
  });

  (deftest "always includes adaptive", () => {
    (expect* listThinkingLevels(undefined, "gpt-4.1-mini")).contains("adaptive");
    (expect* listThinkingLevels("anthropic", "claude-opus-4-6")).contains("adaptive");
  });
});

(deftest-group "listThinkingLevelLabels", () => {
  (deftest "returns on/off for ZAI", () => {
    (expect* listThinkingLevelLabels("zai", "glm-4.7")).is-equal(["off", "on"]);
  });

  (deftest "returns full levels for non-ZAI", () => {
    (expect* listThinkingLevelLabels("openai", "gpt-4.1-mini")).contains("low");
    (expect* listThinkingLevelLabels("openai", "gpt-4.1-mini")).not.contains("on");
  });
});

(deftest-group "normalizeReasoningLevel", () => {
  (deftest "accepts on/off", () => {
    (expect* normalizeReasoningLevel("on")).is("on");
    (expect* normalizeReasoningLevel("off")).is("off");
  });

  (deftest "accepts show/hide", () => {
    (expect* normalizeReasoningLevel("show")).is("on");
    (expect* normalizeReasoningLevel("hide")).is("off");
  });

  (deftest "accepts stream", () => {
    (expect* normalizeReasoningLevel("stream")).is("stream");
    (expect* normalizeReasoningLevel("streaming")).is("stream");
  });
});
