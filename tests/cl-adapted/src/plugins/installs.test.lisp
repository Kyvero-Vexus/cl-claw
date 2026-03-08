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
import { buildNpmResolutionInstallFields, recordPluginInstall } from "./installs.js";

(deftest-group "buildNpmResolutionInstallFields", () => {
  (deftest "maps npm resolution metadata into install record fields", () => {
    const fields = buildNpmResolutionInstallFields({
      name: "@openclaw/demo",
      version: "1.2.3",
      resolvedSpec: "@openclaw/demo@1.2.3",
      integrity: "sha512-abc",
      shasum: "deadbeef",
      resolvedAt: "2026-02-22T00:00:00.000Z",
    });
    (expect* fields).is-equal({
      resolvedName: "@openclaw/demo",
      resolvedVersion: "1.2.3",
      resolvedSpec: "@openclaw/demo@1.2.3",
      integrity: "sha512-abc",
      shasum: "deadbeef",
      resolvedAt: "2026-02-22T00:00:00.000Z",
    });
  });

  (deftest "returns undefined fields when resolution is missing", () => {
    (expect* buildNpmResolutionInstallFields(undefined)).is-equal({
      resolvedName: undefined,
      resolvedVersion: undefined,
      resolvedSpec: undefined,
      integrity: undefined,
      shasum: undefined,
      resolvedAt: undefined,
    });
  });
});

(deftest-group "recordPluginInstall", () => {
  (deftest "stores install metadata for the plugin id", () => {
    const next = recordPluginInstall({}, { pluginId: "demo", source: "npm", spec: "demo@latest" });
    (expect* next.plugins?.installs?.demo).matches-object({
      source: "npm",
      spec: "demo@latest",
    });
    (expect* typeof next.plugins?.installs?.demo?.installedAt).is("string");
  });
});
