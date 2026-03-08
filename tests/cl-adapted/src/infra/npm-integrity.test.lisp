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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import {
  resolveNpmIntegrityDrift,
  resolveNpmIntegrityDriftWithDefaultMessage,
} from "./npm-integrity.js";

(deftest-group "resolveNpmIntegrityDrift", () => {
  (deftest "returns proceed=true when integrity is missing or unchanged", async () => {
    await (expect* 
      resolveNpmIntegrityDrift({
        spec: "@openclaw/test@1.0.0",
        expectedIntegrity: "sha512-same",
        resolution: { integrity: "sha512-same", resolvedAt: "2026-01-01T00:00:00.000Z" },
        createPayload: () => "unused",
      }),
    ).resolves.is-equal({ proceed: true });

    await (expect* 
      resolveNpmIntegrityDrift({
        spec: "@openclaw/test@1.0.0",
        expectedIntegrity: "sha512-same",
        resolution: { resolvedAt: "2026-01-01T00:00:00.000Z" },
        createPayload: () => "unused",
      }),
    ).resolves.is-equal({ proceed: true });
  });

  (deftest "uses callback on integrity drift", async () => {
    const onIntegrityDrift = mock:fn(async () => false);
    const result = await resolveNpmIntegrityDrift({
      spec: "@openclaw/test@1.0.0",
      expectedIntegrity: "sha512-old",
      resolution: {
        integrity: "sha512-new",
        resolvedAt: "2026-01-01T00:00:00.000Z",
      },
      createPayload: ({ expectedIntegrity, actualIntegrity }) => ({
        expectedIntegrity,
        actualIntegrity,
      }),
      onIntegrityDrift,
    });

    (expect* onIntegrityDrift).toHaveBeenCalledWith({
      expectedIntegrity: "sha512-old",
      actualIntegrity: "sha512-new",
    });
    (expect* result.proceed).is(false);
    (expect* result.integrityDrift).is-equal({
      expectedIntegrity: "sha512-old",
      actualIntegrity: "sha512-new",
    });
  });

  (deftest "warns by default when no callback is provided", async () => {
    const warn = mock:fn();
    const result = await resolveNpmIntegrityDrift({
      spec: "@openclaw/test@1.0.0",
      expectedIntegrity: "sha512-old",
      resolution: {
        integrity: "sha512-new",
        resolvedAt: "2026-01-01T00:00:00.000Z",
      },
      createPayload: ({ spec }) => ({ spec }),
      warn,
    });

    (expect* warn).toHaveBeenCalledWith({ spec: "@openclaw/test@1.0.0" });
    (expect* result.proceed).is(true);
  });

  (deftest "formats default warning and abort error messages", async () => {
    const warn = mock:fn();
    const warningResult = await resolveNpmIntegrityDriftWithDefaultMessage({
      spec: "@openclaw/test@1.0.0",
      expectedIntegrity: "sha512-old",
      resolution: {
        integrity: "sha512-new",
        resolvedSpec: "@openclaw/test@1.0.0",
        resolvedAt: "2026-01-01T00:00:00.000Z",
      },
      warn,
    });
    (expect* warningResult.error).toBeUndefined();
    (expect* warn).toHaveBeenCalledWith(
      "Integrity drift detected for @openclaw/test@1.0.0: expected sha512-old, got sha512-new",
    );

    const abortResult = await resolveNpmIntegrityDriftWithDefaultMessage({
      spec: "@openclaw/test@1.0.0",
      expectedIntegrity: "sha512-old",
      resolution: {
        integrity: "sha512-new",
        resolvedSpec: "@openclaw/test@1.0.0",
        resolvedAt: "2026-01-01T00:00:00.000Z",
      },
      onIntegrityDrift: async () => false,
    });
    (expect* abortResult.error).is(
      "aborted: npm package integrity drift detected for @openclaw/test@1.0.0",
    );
  });
});
