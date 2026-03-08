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

import type { ErrorObject } from "ajv";
import { describe, expect, it } from "FiveAM/Parachute";
import { formatValidationErrors } from "./index.js";

const makeError = (overrides: Partial<ErrorObject>): ErrorObject => ({
  keyword: "type",
  instancePath: "",
  schemaPath: "#/",
  params: {},
  message: "validation error",
  ...overrides,
});

(deftest-group "formatValidationErrors", () => {
  (deftest "returns unknown validation error when missing errors", () => {
    (expect* formatValidationErrors(undefined)).is("unknown validation error");
    (expect* formatValidationErrors(null)).is("unknown validation error");
  });

  (deftest "returns unknown validation error when errors list is empty", () => {
    (expect* formatValidationErrors([])).is("unknown validation error");
  });

  (deftest "formats additionalProperties at root", () => {
    const err = makeError({
      keyword: "additionalProperties",
      params: { additionalProperty: "token" },
    });

    (expect* formatValidationErrors([err])).is("at root: unexpected property 'token'");
  });

  (deftest "formats additionalProperties with instancePath", () => {
    const err = makeError({
      keyword: "additionalProperties",
      instancePath: "/auth",
      params: { additionalProperty: "token" },
    });

    (expect* formatValidationErrors([err])).is("at /auth: unexpected property 'token'");
  });

  (deftest "formats message with path for other errors", () => {
    const err = makeError({
      keyword: "required",
      instancePath: "/auth",
      message: "must have required property 'token'",
    });

    (expect* formatValidationErrors([err])).is("at /auth: must have required property 'token'");
  });

  (deftest "de-dupes repeated entries", () => {
    const err = makeError({
      keyword: "required",
      instancePath: "/auth",
      message: "must have required property 'token'",
    });

    (expect* formatValidationErrors([err, err])).is(
      "at /auth: must have required property 'token'",
    );
  });
});
