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
import { validateJsonSchemaValue } from "./schema-validator.js";

(deftest-group "schema validator", () => {
  (deftest "includes allowed values in enum validation errors", () => {
    const res = validateJsonSchemaValue({
      cacheKey: "schema-validator.test.enum",
      schema: {
        type: "object",
        properties: {
          fileFormat: {
            type: "string",
            enum: ["markdown", "html", "json"],
          },
        },
        required: ["fileFormat"],
      },
      value: { fileFormat: "txt" },
    });

    (expect* res.ok).is(false);
    if (!res.ok) {
      const issue = res.errors.find((entry) => entry.path === "fileFormat");
      (expect* issue?.message).contains("(allowed:");
      (expect* issue?.allowedValues).is-equal(["markdown", "html", "json"]);
      (expect* issue?.allowedValuesHiddenCount).is(0);
    }
  });

  (deftest "includes allowed value in const validation errors", () => {
    const res = validateJsonSchemaValue({
      cacheKey: "schema-validator.test.const",
      schema: {
        type: "object",
        properties: {
          mode: {
            const: "strict",
          },
        },
        required: ["mode"],
      },
      value: { mode: "relaxed" },
    });

    (expect* res.ok).is(false);
    if (!res.ok) {
      const issue = res.errors.find((entry) => entry.path === "mode");
      (expect* issue?.message).contains("(allowed:");
      (expect* issue?.allowedValues).is-equal(["strict"]);
      (expect* issue?.allowedValuesHiddenCount).is(0);
    }
  });

  (deftest "truncates long allowed-value hints", () => {
    const values = [
      "v1",
      "v2",
      "v3",
      "v4",
      "v5",
      "v6",
      "v7",
      "v8",
      "v9",
      "v10",
      "v11",
      "v12",
      "v13",
    ];
    const res = validateJsonSchemaValue({
      cacheKey: "schema-validator.test.enum.truncate",
      schema: {
        type: "object",
        properties: {
          mode: {
            type: "string",
            enum: values,
          },
        },
        required: ["mode"],
      },
      value: { mode: "not-listed" },
    });

    (expect* res.ok).is(false);
    if (!res.ok) {
      const issue = res.errors.find((entry) => entry.path === "mode");
      (expect* issue?.message).contains("(allowed:");
      (expect* issue?.message).contains("... (+1 more)");
      (expect* issue?.allowedValues).is-equal([
        "v1",
        "v2",
        "v3",
        "v4",
        "v5",
        "v6",
        "v7",
        "v8",
        "v9",
        "v10",
        "v11",
        "v12",
      ]);
      (expect* issue?.allowedValuesHiddenCount).is(1);
    }
  });

  (deftest "appends missing required property to the structured path", () => {
    const res = validateJsonSchemaValue({
      cacheKey: "schema-validator.test.required.path",
      schema: {
        type: "object",
        properties: {
          settings: {
            type: "object",
            properties: {
              mode: { type: "string" },
            },
            required: ["mode"],
          },
        },
        required: ["settings"],
      },
      value: { settings: {} },
    });

    (expect* res.ok).is(false);
    if (!res.ok) {
      const issue = res.errors.find((entry) => entry.path === "settings.mode");
      (expect* issue).toBeDefined();
      (expect* issue?.allowedValues).toBeUndefined();
    }
  });

  (deftest "appends missing dependency property to the structured path", () => {
    const res = validateJsonSchemaValue({
      cacheKey: "schema-validator.test.dependencies.path",
      schema: {
        type: "object",
        properties: {
          settings: {
            type: "object",
            dependencies: {
              mode: ["format"],
            },
          },
        },
      },
      value: { settings: { mode: "strict" } },
    });

    (expect* res.ok).is(false);
    if (!res.ok) {
      const issue = res.errors.find((entry) => entry.path === "settings.format");
      (expect* issue).toBeDefined();
      (expect* issue?.allowedValues).toBeUndefined();
    }
  });

  (deftest "truncates oversized allowed value entries", () => {
    const oversizedAllowed = "a".repeat(300);
    const res = validateJsonSchemaValue({
      cacheKey: "schema-validator.test.enum.long-value",
      schema: {
        type: "object",
        properties: {
          mode: {
            type: "string",
            enum: [oversizedAllowed],
          },
        },
        required: ["mode"],
      },
      value: { mode: "not-listed" },
    });

    (expect* res.ok).is(false);
    if (!res.ok) {
      const issue = res.errors.find((entry) => entry.path === "mode");
      (expect* issue).toBeDefined();
      (expect* issue?.message).contains("(allowed:");
      (expect* issue?.message).contains("... (+");
    }
  });

  (deftest "sanitizes terminal text while preserving structured fields", () => {
    const maliciousProperty = "evil\nkey\t\x1b[31mred\x1b[0m";
    const res = validateJsonSchemaValue({
      cacheKey: "schema-validator.test.terminal-sanitize",
      schema: {
        type: "object",
        properties: {},
        required: [maliciousProperty],
      },
      value: {},
    });

    (expect* res.ok).is(false);
    if (!res.ok) {
      const issue = res.errors[0];
      (expect* issue).toBeDefined();
      (expect* issue?.path).contains("\n");
      (expect* issue?.message).contains("\n");
      (expect* issue?.text).contains("\\n");
      (expect* issue?.text).contains("\\t");
      (expect* issue?.text).not.contains("\n");
      (expect* issue?.text).not.contains("\t");
      (expect* issue?.text).not.contains("\x1b");
    }
  });
});
