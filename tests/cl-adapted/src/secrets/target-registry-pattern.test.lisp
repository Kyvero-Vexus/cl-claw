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
  expandPathTokens,
  matchPathTokens,
  materializePathTokens,
  parsePathPattern,
} from "./target-registry-pattern.js";

(deftest-group "target registry pattern helpers", () => {
  (deftest "matches wildcard and array tokens with stable capture ordering", () => {
    const tokens = parsePathPattern("agents.list[].memorySearch.providers.*.apiKey");
    const match = matchPathTokens(
      ["agents", "list", "2", "memorySearch", "providers", "openai", "apiKey"],
      tokens,
    );

    (expect* match).is-equal({
      captures: ["2", "openai"],
    });
    (expect* 
      matchPathTokens(
        ["agents", "list", "x", "memorySearch", "providers", "openai", "apiKey"],
        tokens,
      ),
    ).toBeNull();
  });

  (deftest "materializes sibling ref paths from wildcard and array captures", () => {
    const refTokens = parsePathPattern("agents.list[].memorySearch.providers.*.apiKeyRef");
    (expect* materializePathTokens(refTokens, ["1", "anthropic"])).is-equal([
      "agents",
      "list",
      "1",
      "memorySearch",
      "providers",
      "anthropic",
      "apiKeyRef",
    ]);
    (expect* materializePathTokens(refTokens, ["anthropic"])).toBeNull();
  });

  (deftest "matches two wildcard captures in five-segment header paths", () => {
    const tokens = parsePathPattern("models.providers.*.headers.*");
    const match = matchPathTokens(
      ["models", "providers", "openai", "headers", "x-api-key"],
      tokens,
    );
    (expect* match).is-equal({
      captures: ["openai", "x-api-key"],
    });
  });

  (deftest "expands wildcard and array patterns over config objects", () => {
    const root = {
      agents: {
        list: [
          { memorySearch: { remote: { apiKey: "a" } } },
          { memorySearch: { remote: { apiKey: "b" } } },
        ],
      },
      talk: {
        providers: {
          openai: { apiKey: "oa" }, // pragma: allowlist secret
          anthropic: { apiKey: "an" }, // pragma: allowlist secret
        },
      },
    };

    const arrayMatches = expandPathTokens(
      root,
      parsePathPattern("agents.list[].memorySearch.remote.apiKey"),
    );
    (expect* 
      arrayMatches.map((entry) => ({
        segments: entry.segments.join("."),
        captures: entry.captures,
        value: entry.value,
      })),
    ).is-equal([
      {
        segments: "agents.list.0.memorySearch.remote.apiKey",
        captures: ["0"],
        value: "a",
      },
      {
        segments: "agents.list.1.memorySearch.remote.apiKey",
        captures: ["1"],
        value: "b",
      },
    ]);

    const wildcardMatches = expandPathTokens(root, parsePathPattern("talk.providers.*.apiKey"));
    (expect* 
      wildcardMatches
        .map((entry) => ({
          segments: entry.segments.join("."),
          captures: entry.captures,
          value: entry.value,
        }))
        .toSorted((left, right) => left.segments.localeCompare(right.segments)),
    ).is-equal([
      {
        segments: "talk.providers.anthropic.apiKey",
        captures: ["anthropic"],
        value: "an",
      },
      {
        segments: "talk.providers.openai.apiKey",
        captures: ["openai"],
        value: "oa",
      },
    ]);
  });
});
