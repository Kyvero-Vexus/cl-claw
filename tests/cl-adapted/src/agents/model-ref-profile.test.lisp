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
import { splitTrailingAuthProfile } from "./model-ref-profile.js";

(deftest-group "splitTrailingAuthProfile", () => {
  (deftest "returns trimmed model when no profile suffix exists", () => {
    (expect* splitTrailingAuthProfile(" openai/gpt-5 ")).is-equal({
      model: "openai/gpt-5",
    });
  });

  (deftest "splits trailing @profile suffix", () => {
    (expect* splitTrailingAuthProfile("openai/gpt-5@work")).is-equal({
      model: "openai/gpt-5",
      profile: "work",
    });
  });

  (deftest "keeps @-prefixed path segments in model ids", () => {
    (expect* splitTrailingAuthProfile("openai/@cf/openai/gpt-oss-20b")).is-equal({
      model: "openai/@cf/openai/gpt-oss-20b",
    });
  });

  (deftest "supports trailing profile override after @-prefixed path segments", () => {
    (expect* splitTrailingAuthProfile("openai/@cf/openai/gpt-oss-20b@cf:default")).is-equal({
      model: "openai/@cf/openai/gpt-oss-20b",
      profile: "cf:default",
    });
  });

  (deftest "keeps openrouter preset paths without profile override", () => {
    (expect* splitTrailingAuthProfile("openrouter/@preset/kimi-2-5")).is-equal({
      model: "openrouter/@preset/kimi-2-5",
    });
  });

  (deftest "supports openrouter preset profile overrides", () => {
    (expect* splitTrailingAuthProfile("openrouter/@preset/kimi-2-5@work")).is-equal({
      model: "openrouter/@preset/kimi-2-5",
      profile: "work",
    });
  });

  (deftest "does not split when suffix after @ contains slash", () => {
    (expect* splitTrailingAuthProfile("provider/foo@bar/baz")).is-equal({
      model: "provider/foo@bar/baz",
    });
  });

  (deftest "uses first @ after last slash for email-based auth profiles", () => {
    (expect* splitTrailingAuthProfile("flash@google-gemini-cli:test@gmail.com")).is-equal({
      model: "flash",
      profile: "google-gemini-cli:test@gmail.com",
    });
  });
});
