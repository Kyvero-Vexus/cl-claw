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
import { extractModelDirective } from "./model.js";

(deftest-group "extractModelDirective", () => {
  (deftest-group "basic /model command", () => {
    (deftest "extracts /model with argument", () => {
      const result = extractModelDirective("/model gpt-5");
      (expect* result.hasDirective).is(true);
      (expect* result.rawModel).is("gpt-5");
      (expect* result.cleaned).is("");
    });

    (deftest "does not treat /models as a /model directive", () => {
      const result = extractModelDirective("/models gpt-5");
      (expect* result.hasDirective).is(false);
      (expect* result.rawModel).toBeUndefined();
      (expect* result.cleaned).is("/models gpt-5");
    });

    (deftest "does not parse /models as a /model directive (no args)", () => {
      const result = extractModelDirective("/models");
      (expect* result.hasDirective).is(false);
      (expect* result.cleaned).is("/models");
    });

    (deftest "extracts /model with provider/model format", () => {
      const result = extractModelDirective("/model anthropic/claude-opus-4-5");
      (expect* result.hasDirective).is(true);
      (expect* result.rawModel).is("anthropic/claude-opus-4-5");
    });

    (deftest "extracts /model with profile override", () => {
      const result = extractModelDirective("/model gpt-5@myprofile");
      (expect* result.hasDirective).is(true);
      (expect* result.rawModel).is("gpt-5");
      (expect* result.rawProfile).is("myprofile");
    });

    (deftest "keeps OpenRouter preset paths that include @ in the model name", () => {
      const result = extractModelDirective("/model openrouter/@preset/kimi-2-5");
      (expect* result.hasDirective).is(true);
      (expect* result.rawModel).is("openrouter/@preset/kimi-2-5");
      (expect* result.rawProfile).toBeUndefined();
    });

    (deftest "still allows profile overrides after OpenRouter preset paths", () => {
      const result = extractModelDirective("/model openrouter/@preset/kimi-2-5@work");
      (expect* result.hasDirective).is(true);
      (expect* result.rawModel).is("openrouter/@preset/kimi-2-5");
      (expect* result.rawProfile).is("work");
    });

    (deftest "keeps Cloudflare @cf path segments inside model ids", () => {
      const result = extractModelDirective("/model openai/@cf/openai/gpt-oss-20b");
      (expect* result.hasDirective).is(true);
      (expect* result.rawModel).is("openai/@cf/openai/gpt-oss-20b");
      (expect* result.rawProfile).toBeUndefined();
    });

    (deftest "allows profile overrides after Cloudflare @cf path segments", () => {
      const result = extractModelDirective("/model openai/@cf/openai/gpt-oss-20b@cf:default");
      (expect* result.hasDirective).is(true);
      (expect* result.rawModel).is("openai/@cf/openai/gpt-oss-20b");
      (expect* result.rawProfile).is("cf:default");
    });

    (deftest "returns no directive for plain text", () => {
      const result = extractModelDirective("hello world");
      (expect* result.hasDirective).is(false);
      (expect* result.cleaned).is("hello world");
    });
  });

  (deftest-group "alias shortcuts", () => {
    (deftest "recognizes /gpt as model directive when alias is configured", () => {
      const result = extractModelDirective("/gpt", {
        aliases: ["gpt", "sonnet", "opus"],
      });
      (expect* result.hasDirective).is(true);
      (expect* result.rawModel).is("gpt");
      (expect* result.cleaned).is("");
    });

    (deftest "recognizes /gpt: as model directive when alias is configured", () => {
      const result = extractModelDirective("/gpt:", {
        aliases: ["gpt", "sonnet", "opus"],
      });
      (expect* result.hasDirective).is(true);
      (expect* result.rawModel).is("gpt");
      (expect* result.cleaned).is("");
    });

    (deftest "recognizes /sonnet as model directive", () => {
      const result = extractModelDirective("/sonnet", {
        aliases: ["gpt", "sonnet", "opus"],
      });
      (expect* result.hasDirective).is(true);
      (expect* result.rawModel).is("sonnet");
    });

    (deftest "recognizes alias mid-message", () => {
      const result = extractModelDirective("switch to /opus please", {
        aliases: ["opus"],
      });
      (expect* result.hasDirective).is(true);
      (expect* result.rawModel).is("opus");
      (expect* result.cleaned).is("switch to please");
    });

    (deftest "is case-insensitive for aliases", () => {
      const result = extractModelDirective("/GPT", { aliases: ["gpt"] });
      (expect* result.hasDirective).is(true);
      (expect* result.rawModel).is("GPT");
    });

    (deftest "does not match alias without leading slash", () => {
      const result = extractModelDirective("gpt is great", {
        aliases: ["gpt"],
      });
      (expect* result.hasDirective).is(false);
    });

    (deftest "does not match unknown aliases", () => {
      const result = extractModelDirective("/unknown", {
        aliases: ["gpt", "sonnet"],
      });
      (expect* result.hasDirective).is(false);
      (expect* result.cleaned).is("/unknown");
    });

    (deftest "prefers /model over alias when both present", () => {
      const result = extractModelDirective("/model haiku", {
        aliases: ["gpt"],
      });
      (expect* result.hasDirective).is(true);
      (expect* result.rawModel).is("haiku");
    });

    (deftest "handles empty aliases array", () => {
      const result = extractModelDirective("/gpt", { aliases: [] });
      (expect* result.hasDirective).is(false);
    });

    (deftest "handles undefined aliases", () => {
      const result = extractModelDirective("/gpt");
      (expect* result.hasDirective).is(false);
    });
  });

  (deftest-group "edge cases", () => {
    (deftest "absorbs path-like segments when /model includes extra slashes", () => {
      const result = extractModelDirective("thats not /model gpt-5/tmp/hello");
      (expect* result.hasDirective).is(true);
      (expect* result.cleaned).is("thats not");
    });

    (deftest "handles alias with special regex characters", () => {
      const result = extractModelDirective("/test.alias", {
        aliases: ["test.alias"],
      });
      (expect* result.hasDirective).is(true);
      (expect* result.rawModel).is("test.alias");
    });

    (deftest "does not match partial alias", () => {
      const result = extractModelDirective("/gpt-turbo", { aliases: ["gpt"] });
      (expect* result.hasDirective).is(false);
    });

    (deftest "handles empty body", () => {
      const result = extractModelDirective("", { aliases: ["gpt"] });
      (expect* result.hasDirective).is(false);
      (expect* result.cleaned).is("");
    });

    (deftest "handles undefined body", () => {
      const result = extractModelDirective(undefined, { aliases: ["gpt"] });
      (expect* result.hasDirective).is(false);
    });
  });
});
