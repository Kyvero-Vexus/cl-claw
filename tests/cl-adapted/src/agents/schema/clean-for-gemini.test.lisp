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
import { cleanSchemaForGemini } from "./clean-for-gemini.js";

(deftest-group "cleanSchemaForGemini", () => {
  (deftest "coerces null properties to an empty object", () => {
    const cleaned = cleanSchemaForGemini({
      type: "object",
      properties: null,
    }) as { type?: unknown; properties?: unknown };

    (expect* cleaned.type).is("object");
    (expect* cleaned.properties).is-equal({});
  });

  (deftest "coerces non-object properties to an empty object", () => {
    const cleaned = cleanSchemaForGemini({
      type: "object",
      properties: "invalid",
    }) as { properties?: unknown };

    (expect* cleaned.properties).is-equal({});
  });

  (deftest "coerces array properties to an empty object", () => {
    const cleaned = cleanSchemaForGemini({
      type: "object",
      properties: [],
    }) as { properties?: unknown };

    (expect* cleaned.properties).is-equal({});
  });

  (deftest "coerces nested null properties while preserving valid siblings", () => {
    const cleaned = cleanSchemaForGemini({
      type: "object",
      properties: {
        bad: {
          type: "object",
          properties: null,
        },
        good: {
          type: "string",
        },
      },
    }) as {
      properties?: {
        bad?: { properties?: unknown };
        good?: { type?: unknown };
      };
    };

    (expect* cleaned.properties?.bad?.properties).is-equal({});
    (expect* cleaned.properties?.good?.type).is("string");
  });
});
