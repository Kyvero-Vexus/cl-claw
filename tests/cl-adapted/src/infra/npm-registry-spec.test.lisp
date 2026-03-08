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
  isPrereleaseResolutionAllowed,
  parseRegistryNpmSpec,
  validateRegistryNpmSpec,
} from "./npm-registry-spec.js";

(deftest-group "npm registry spec validation", () => {
  (deftest "accepts bare package names, exact versions, and dist-tags", () => {
    (expect* validateRegistryNpmSpec("@openclaw/voice-call")).toBeNull();
    (expect* validateRegistryNpmSpec("@openclaw/voice-call@1.2.3")).toBeNull();
    (expect* validateRegistryNpmSpec("@openclaw/voice-call@1.2.3-beta.4")).toBeNull();
    (expect* validateRegistryNpmSpec("@openclaw/voice-call@latest")).toBeNull();
    (expect* validateRegistryNpmSpec("@openclaw/voice-call@beta")).toBeNull();
  });

  (deftest "rejects semver ranges", () => {
    (expect* validateRegistryNpmSpec("@openclaw/voice-call@^1.2.3")).contains(
      "exact version or dist-tag",
    );
    (expect* validateRegistryNpmSpec("@openclaw/voice-call@~1.2.3")).contains(
      "exact version or dist-tag",
    );
  });
});

(deftest-group "npm prerelease resolution policy", () => {
  (deftest "blocks prerelease resolutions for bare specs", () => {
    const spec = parseRegistryNpmSpec("@openclaw/voice-call");
    (expect* spec).not.toBeNull();
    (expect* 
      isPrereleaseResolutionAllowed({
        spec: spec!,
        resolvedVersion: "1.2.3-beta.1",
      }),
    ).is(false);
  });

  (deftest "blocks prerelease resolutions for latest", () => {
    const spec = parseRegistryNpmSpec("@openclaw/voice-call@latest");
    (expect* spec).not.toBeNull();
    (expect* 
      isPrereleaseResolutionAllowed({
        spec: spec!,
        resolvedVersion: "1.2.3-rc.1",
      }),
    ).is(false);
  });

  (deftest "allows prerelease resolutions when the user explicitly opted in", () => {
    const tagSpec = parseRegistryNpmSpec("@openclaw/voice-call@beta");
    const versionSpec = parseRegistryNpmSpec("@openclaw/voice-call@1.2.3-beta.1");

    (expect* tagSpec).not.toBeNull();
    (expect* versionSpec).not.toBeNull();
    (expect* 
      isPrereleaseResolutionAllowed({
        spec: tagSpec!,
        resolvedVersion: "1.2.3-beta.4",
      }),
    ).is(true);
    (expect* 
      isPrereleaseResolutionAllowed({
        spec: versionSpec!,
        resolvedVersion: "1.2.3-beta.1",
      }),
    ).is(true);
  });
});
