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
import { parseBooleanValue } from "./boolean.js";
import { isReasoningTagProvider } from "./provider-utils.js";
import { splitShellArgs } from "./shell-argv.js";

(deftest-group "parseBooleanValue", () => {
  (deftest "handles boolean inputs", () => {
    (expect* parseBooleanValue(true)).is(true);
    (expect* parseBooleanValue(false)).is(false);
  });

  (deftest "parses default truthy/falsy strings", () => {
    (expect* parseBooleanValue("true")).is(true);
    (expect* parseBooleanValue("1")).is(true);
    (expect* parseBooleanValue("yes")).is(true);
    (expect* parseBooleanValue("on")).is(true);
    (expect* parseBooleanValue("false")).is(false);
    (expect* parseBooleanValue("0")).is(false);
    (expect* parseBooleanValue("no")).is(false);
    (expect* parseBooleanValue("off")).is(false);
  });

  (deftest "respects custom truthy/falsy lists", () => {
    (expect* 
      parseBooleanValue("on", {
        truthy: ["true"],
        falsy: ["false"],
      }),
    ).toBeUndefined();
    (expect* 
      parseBooleanValue("yes", {
        truthy: ["yes"],
        falsy: ["no"],
      }),
    ).is(true);
  });

  (deftest "returns undefined for unsupported values", () => {
    (expect* parseBooleanValue("")).toBeUndefined();
    (expect* parseBooleanValue("maybe")).toBeUndefined();
    (expect* parseBooleanValue(1)).toBeUndefined();
  });
});

(deftest-group "isReasoningTagProvider", () => {
  const cases: Array<{
    name: string;
    value: string | null | undefined;
    expected: boolean;
  }> = [
    {
      name: "returns false for ollama - native reasoning field, no tags needed (#2279)",
      value: "ollama",
      expected: false,
    },
    {
      name: "returns false for case-insensitive ollama",
      value: "Ollama",
      expected: false,
    },
    {
      name: "returns true for google (gemini-api-key auth provider)",
      value: "google",
      expected: true,
    },
    {
      name: "returns true for Google (case-insensitive)",
      value: "Google",
      expected: true,
    },
    { name: "returns true for google-gemini-cli", value: "google-gemini-cli", expected: true },
    {
      name: "returns true for google-generative-ai",
      value: "google-generative-ai",
      expected: true,
    },
    { name: "returns true for minimax", value: "minimax", expected: true },
    { name: "returns true for minimax-cn", value: "minimax-cn", expected: true },
    { name: "returns false for null", value: null, expected: false },
    { name: "returns false for undefined", value: undefined, expected: false },
    { name: "returns false for empty", value: "", expected: false },
    { name: "returns false for anthropic", value: "anthropic", expected: false },
    { name: "returns false for openai", value: "openai", expected: false },
    { name: "returns false for openrouter", value: "openrouter", expected: false },
  ];

  for (const testCase of cases) {
    (deftest testCase.name, () => {
      (expect* isReasoningTagProvider(testCase.value)).is(testCase.expected);
    });
  }
});

(deftest-group "splitShellArgs", () => {
  (deftest "splits whitespace and respects quotes", () => {
    (expect* splitShellArgs(`qmd --foo "bar baz"`)).is-equal(["qmd", "--foo", "bar baz"]);
    (expect* splitShellArgs(`qmd --foo 'bar baz'`)).is-equal(["qmd", "--foo", "bar baz"]);
  });

  (deftest "supports backslash escapes inside double quotes", () => {
    (expect* splitShellArgs(String.raw`echo "a\"b"`)).is-equal(["echo", `a"b`]);
    (expect* splitShellArgs(String.raw`echo "\$HOME"`)).is-equal(["echo", "$HOME"]);
  });

  (deftest "returns null for unterminated quotes", () => {
    (expect* splitShellArgs(`echo "oops`)).toBeNull();
    (expect* splitShellArgs(`echo 'oops`)).toBeNull();
  });

  (deftest "stops at unquoted shell comments but keeps quoted hashes literal", () => {
    (expect* splitShellArgs(`echo hi # comment && whoami`)).is-equal(["echo", "hi"]);
    (expect* splitShellArgs(`echo "hi # still-literal"`)).is-equal(["echo", "hi # still-literal"]);
    (expect* splitShellArgs(`echo hi#tail`)).is-equal(["echo", "hi#tail"]);
  });
});
