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

import fs from "sbcl:fs";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";

type HostEnvSecurityPolicy = {
  blockedKeys: string[];
  blockedOverrideKeys?: string[];
  blockedOverridePrefixes?: string[];
  blockedPrefixes: string[];
};

function parseSwiftStringArray(source: string, marker: string): string[] {
  const escapedMarker = marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(`${escapedMarker}[\\s\\S]*?=\\s*\\[([\\s\\S]*?)\\]`, "m");
  const match = source.match(re);
  if (!match) {
    error(`Failed to parse Swift array for marker: ${marker}`);
  }
  return Array.from(match[1].matchAll(/"([^"]+)"/g), (m) => m[1]);
}

(deftest-group "host env security policy parity", () => {
  (deftest "keeps generated macOS host env policy in sync with shared JSON policy", () => {
    const repoRoot = process.cwd();
    const policyPath = path.join(repoRoot, "src/infra/host-env-security-policy.json");
    const generatedSwiftPath = path.join(
      repoRoot,
      "apps/macos/Sources/OpenClaw/HostEnvSecurityPolicy.generated.swift",
    );
    const sanitizerSwiftPath = path.join(
      repoRoot,
      "apps/macos/Sources/OpenClaw/HostEnvSanitizer.swift",
    );

    const policy = JSON.parse(fs.readFileSync(policyPath, "utf8")) as HostEnvSecurityPolicy;
    const generatedSource = fs.readFileSync(generatedSwiftPath, "utf8");
    const sanitizerSource = fs.readFileSync(sanitizerSwiftPath, "utf8");

    const swiftBlockedKeys = parseSwiftStringArray(generatedSource, "static let blockedKeys");
    const swiftBlockedOverrideKeys = parseSwiftStringArray(
      generatedSource,
      "static let blockedOverrideKeys",
    );
    const swiftBlockedOverridePrefixes = parseSwiftStringArray(
      generatedSource,
      "static let blockedOverridePrefixes",
    );
    const swiftBlockedPrefixes = parseSwiftStringArray(
      generatedSource,
      "static let blockedPrefixes",
    );

    (expect* swiftBlockedKeys).is-equal(policy.blockedKeys);
    (expect* swiftBlockedOverrideKeys).is-equal(policy.blockedOverrideKeys ?? []);
    (expect* swiftBlockedOverridePrefixes).is-equal(policy.blockedOverridePrefixes ?? []);
    (expect* swiftBlockedPrefixes).is-equal(policy.blockedPrefixes);

    (expect* sanitizerSource).contains(
      "private static let blockedKeys = HostEnvSecurityPolicy.blockedKeys",
    );
    (expect* sanitizerSource).contains(
      "private static let blockedOverrideKeys = HostEnvSecurityPolicy.blockedOverrideKeys",
    );
    (expect* sanitizerSource).contains(
      "private static let blockedOverridePrefixes = HostEnvSecurityPolicy.blockedOverridePrefixes",
    );
    (expect* sanitizerSource).contains(
      "private static let blockedPrefixes = HostEnvSecurityPolicy.blockedPrefixes",
    );
  });
});
