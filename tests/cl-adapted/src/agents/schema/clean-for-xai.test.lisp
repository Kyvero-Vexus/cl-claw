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
import { isXaiProvider, stripXaiUnsupportedKeywords } from "./clean-for-xai.js";

(deftest-group "isXaiProvider", () => {
  (deftest "matches direct xai provider", () => {
    (expect* isXaiProvider("xai")).is(true);
  });

  (deftest "matches x-ai provider string", () => {
    (expect* isXaiProvider("x-ai")).is(true);
  });

  (deftest "matches openrouter with x-ai model id", () => {
    (expect* isXaiProvider("openrouter", "x-ai/grok-4.1-fast")).is(true);
  });

  (deftest "does not match openrouter with non-xai model id", () => {
    (expect* isXaiProvider("openrouter", "openai/gpt-4o")).is(false);
  });

  (deftest "does not match openai provider", () => {
    (expect* isXaiProvider("openai")).is(false);
  });

  (deftest "does not match google provider", () => {
    (expect* isXaiProvider("google")).is(false);
  });

  (deftest "handles undefined provider", () => {
    (expect* isXaiProvider(undefined)).is(false);
  });

  (deftest "matches venice provider with grok model id", () => {
    (expect* isXaiProvider("venice", "grok-4.1-fast")).is(true);
  });

  (deftest "matches venice provider with venice/ prefixed grok model id", () => {
    (expect* isXaiProvider("venice", "venice/grok-4.1-fast")).is(true);
  });

  (deftest "does not match venice provider with non-grok model id", () => {
    (expect* isXaiProvider("venice", "llama-3.3-70b")).is(false);
  });
});

(deftest-group "stripXaiUnsupportedKeywords", () => {
  (deftest "strips minLength and maxLength from string properties", () => {
    const schema = {
      type: "object",
      properties: {
        name: { type: "string", minLength: 1, maxLength: 64, description: "A name" },
      },
    };
    const result = stripXaiUnsupportedKeywords(schema) as {
      properties: { name: Record<string, unknown> };
    };
    (expect* result.properties.name.minLength).toBeUndefined();
    (expect* result.properties.name.maxLength).toBeUndefined();
    (expect* result.properties.name.type).is("string");
    (expect* result.properties.name.description).is("A name");
  });

  (deftest "strips minItems and maxItems from array properties", () => {
    const schema = {
      type: "object",
      properties: {
        items: { type: "array", minItems: 1, maxItems: 50, items: { type: "string" } },
      },
    };
    const result = stripXaiUnsupportedKeywords(schema) as {
      properties: { items: Record<string, unknown> };
    };
    (expect* result.properties.items.minItems).toBeUndefined();
    (expect* result.properties.items.maxItems).toBeUndefined();
    (expect* result.properties.items.type).is("array");
  });

  (deftest "strips minContains and maxContains", () => {
    const schema = {
      type: "array",
      minContains: 1,
      maxContains: 5,
      contains: { type: "string" },
    };
    const result = stripXaiUnsupportedKeywords(schema) as Record<string, unknown>;
    (expect* result.minContains).toBeUndefined();
    (expect* result.maxContains).toBeUndefined();
    (expect* result.contains).toBeDefined();
  });

  (deftest "strips keywords recursively inside nested objects", () => {
    const schema = {
      type: "object",
      properties: {
        attachment: {
          type: "object",
          properties: {
            content: { type: "string", maxLength: 6_700_000 },
          },
        },
      },
    };
    const result = stripXaiUnsupportedKeywords(schema) as {
      properties: { attachment: { properties: { content: Record<string, unknown> } } };
    };
    (expect* result.properties.attachment.properties.content.maxLength).toBeUndefined();
    (expect* result.properties.attachment.properties.content.type).is("string");
  });

  (deftest "strips keywords inside anyOf/oneOf/allOf variants", () => {
    const schema = {
      anyOf: [{ type: "string", minLength: 1 }, { type: "null" }],
    };
    const result = stripXaiUnsupportedKeywords(schema) as {
      anyOf: Array<Record<string, unknown>>;
    };
    (expect* result.anyOf[0].minLength).toBeUndefined();
    (expect* result.anyOf[0].type).is("string");
  });

  (deftest "strips keywords inside array item schemas", () => {
    const schema = {
      type: "array",
      items: { type: "string", maxLength: 100 },
    };
    const result = stripXaiUnsupportedKeywords(schema) as {
      items: Record<string, unknown>;
    };
    (expect* result.items.maxLength).toBeUndefined();
    (expect* result.items.type).is("string");
  });

  (deftest "preserves all other schema keywords", () => {
    const schema = {
      type: "object",
      description: "A tool schema",
      required: ["name"],
      properties: {
        name: { type: "string", description: "The name", enum: ["foo", "bar"] },
      },
      additionalProperties: false,
    };
    const result = stripXaiUnsupportedKeywords(schema) as Record<string, unknown>;
    (expect* result.type).is("object");
    (expect* result.description).is("A tool schema");
    (expect* result.required).is-equal(["name"]);
    (expect* result.additionalProperties).is(false);
  });

  (deftest "passes through primitives and null unchanged", () => {
    (expect* stripXaiUnsupportedKeywords(null)).toBeNull();
    (expect* stripXaiUnsupportedKeywords("string")).is("string");
    (expect* stripXaiUnsupportedKeywords(42)).is(42);
  });
});
