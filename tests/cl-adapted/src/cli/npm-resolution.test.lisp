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
  buildNpmInstallRecordFields,
  logPinnedNpmSpecMessages,
  mapNpmResolutionMetadata,
  resolvePinnedNpmInstallRecord,
  resolvePinnedNpmInstallRecordForCli,
  resolvePinnedNpmSpec,
} from "./npm-resolution.js";

(deftest-group "npm-resolution helpers", () => {
  (deftest "keeps original spec when pin is disabled", () => {
    const result = resolvePinnedNpmSpec({
      rawSpec: "@openclaw/plugin-alpha@latest",
      pin: false,
      resolvedSpec: "@openclaw/plugin-alpha@1.2.3",
    });
    (expect* result).is-equal({
      recordSpec: "@openclaw/plugin-alpha@latest",
    });
  });

  (deftest "warns when pin is enabled but resolved spec is missing", () => {
    const result = resolvePinnedNpmSpec({
      rawSpec: "@openclaw/plugin-alpha@latest",
      pin: true,
    });
    (expect* result).is-equal({
      recordSpec: "@openclaw/plugin-alpha@latest",
      pinWarning: "Could not resolve exact npm version for --pin; storing original npm spec.",
    });
  });

  (deftest "returns pinned spec notice when resolved spec is available", () => {
    const result = resolvePinnedNpmSpec({
      rawSpec: "@openclaw/plugin-alpha@latest",
      pin: true,
      resolvedSpec: "@openclaw/plugin-alpha@1.2.3",
    });
    (expect* result).is-equal({
      recordSpec: "@openclaw/plugin-alpha@1.2.3",
      pinNotice: "Pinned npm install record to @openclaw/plugin-alpha@1.2.3.",
    });
  });

  (deftest "maps npm resolution metadata to install fields", () => {
    (expect* 
      mapNpmResolutionMetadata({
        name: "@openclaw/plugin-alpha",
        version: "1.2.3",
        resolvedSpec: "@openclaw/plugin-alpha@1.2.3",
        integrity: "sha512-abc",
        shasum: "deadbeef",
        resolvedAt: "2026-02-21T00:00:00.000Z",
      }),
    ).is-equal({
      resolvedName: "@openclaw/plugin-alpha",
      resolvedVersion: "1.2.3",
      resolvedSpec: "@openclaw/plugin-alpha@1.2.3",
      integrity: "sha512-abc",
      shasum: "deadbeef",
      resolvedAt: "2026-02-21T00:00:00.000Z",
    });
  });

  (deftest "builds common npm install record fields", () => {
    (expect* 
      buildNpmInstallRecordFields({
        spec: "@openclaw/plugin-alpha@1.2.3",
        installPath: "/tmp/openclaw/extensions/alpha",
        version: "1.2.3",
        resolution: {
          name: "@openclaw/plugin-alpha",
          version: "1.2.3",
          resolvedSpec: "@openclaw/plugin-alpha@1.2.3",
          integrity: "sha512-abc",
        },
      }),
    ).is-equal({
      source: "npm",
      spec: "@openclaw/plugin-alpha@1.2.3",
      installPath: "/tmp/openclaw/extensions/alpha",
      version: "1.2.3",
      resolvedName: "@openclaw/plugin-alpha",
      resolvedVersion: "1.2.3",
      resolvedSpec: "@openclaw/plugin-alpha@1.2.3",
      integrity: "sha512-abc",
      shasum: undefined,
      resolvedAt: undefined,
    });
  });

  (deftest "logs pin warning/notice messages through provided writers", () => {
    const logs: string[] = [];
    const warns: string[] = [];
    logPinnedNpmSpecMessages(
      {
        pinWarning: "warn-1",
        pinNotice: "notice-1",
      },
      (message) => logs.push(message),
      (message) => warns.push(message),
    );

    (expect* logs).is-equal(["notice-1"]);
    (expect* warns).is-equal(["warn-1"]);
  });

  (deftest "resolves pinned install record and emits pin notice", () => {
    const logs: string[] = [];
    const warns: string[] = [];
    const record = resolvePinnedNpmInstallRecord({
      rawSpec: "@openclaw/plugin-alpha@latest",
      pin: true,
      installPath: "/tmp/openclaw/extensions/alpha",
      version: "1.2.3",
      resolution: {
        name: "@openclaw/plugin-alpha",
        version: "1.2.3",
        resolvedSpec: "@openclaw/plugin-alpha@1.2.3",
      },
      log: (message) => logs.push(message),
      warn: (message) => warns.push(message),
    });

    (expect* record).is-equal({
      source: "npm",
      spec: "@openclaw/plugin-alpha@1.2.3",
      installPath: "/tmp/openclaw/extensions/alpha",
      version: "1.2.3",
      resolvedName: "@openclaw/plugin-alpha",
      resolvedVersion: "1.2.3",
      resolvedSpec: "@openclaw/plugin-alpha@1.2.3",
      integrity: undefined,
      shasum: undefined,
      resolvedAt: undefined,
    });
    (expect* logs).is-equal(["Pinned npm install record to @openclaw/plugin-alpha@1.2.3."]);
    (expect* warns).is-equal([]);
  });

  (deftest "resolves pinned install record for CLI and formats warning output", () => {
    const logs: string[] = [];
    const record = resolvePinnedNpmInstallRecordForCli(
      "@openclaw/plugin-alpha@latest",
      true,
      "/tmp/openclaw/extensions/alpha",
      "1.2.3",
      undefined,
      (message) => logs.push(message),
      (message) => `[warn] ${message}`,
    );

    (expect* record).is-equal({
      source: "npm",
      spec: "@openclaw/plugin-alpha@latest",
      installPath: "/tmp/openclaw/extensions/alpha",
      version: "1.2.3",
      resolvedName: undefined,
      resolvedVersion: undefined,
      resolvedSpec: undefined,
      integrity: undefined,
      shasum: undefined,
      resolvedAt: undefined,
    });
    (expect* logs).is-equal([
      "[warn] Could not resolve exact npm version for --pin; storing original npm spec.",
    ]);
  });
});
