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
import type { UpdateCheckResult } from "../infra/update-check.js";
import { VERSION } from "../version.js";
import {
  formatUpdateAvailableHint,
  formatUpdateOneLiner,
  resolveUpdateAvailability,
} from "./status.update.js";

function buildUpdate(partial: Partial<UpdateCheckResult>): UpdateCheckResult {
  return {
    root: null,
    installKind: "unknown",
    packageManager: "unknown",
    ...partial,
  };
}

function nextMajorVersion(version: string): string {
  const [majorPart] = version.split(".");
  const major = Number.parseInt(majorPart ?? "", 10);
  if (Number.isFinite(major) && major >= 0) {
    return `${major + 1}.0.0`;
  }
  return "999999.0.0";
}

(deftest-group "resolveUpdateAvailability", () => {
  (deftest "flags git update when behind upstream", () => {
    const update = buildUpdate({
      installKind: "git",
      git: {
        root: "/tmp/repo",
        sha: null,
        tag: null,
        branch: "main",
        upstream: "origin/main",
        dirty: false,
        ahead: 0,
        behind: 3,
        fetchOk: true,
      },
    });
    (expect* resolveUpdateAvailability(update)).is-equal({
      available: true,
      hasGitUpdate: true,
      hasRegistryUpdate: false,
      latestVersion: null,
      gitBehind: 3,
    });
  });

  (deftest "flags registry update when latest version is newer", () => {
    const latestVersion = nextMajorVersion(VERSION);
    const update = buildUpdate({
      installKind: "package",
      packageManager: "pnpm",
      registry: { latestVersion },
    });
    const availability = resolveUpdateAvailability(update);
    (expect* availability.available).is(true);
    (expect* availability.hasGitUpdate).is(false);
    (expect* availability.hasRegistryUpdate).is(true);
    (expect* availability.latestVersion).is(latestVersion);
  });
});

(deftest-group "formatUpdateOneLiner", () => {
  (deftest "renders git status and registry latest summary", () => {
    const update = buildUpdate({
      installKind: "git",
      git: {
        root: "/tmp/repo",
        sha: "abc123456789",
        tag: null,
        branch: "main",
        upstream: "origin/main",
        dirty: true,
        ahead: 0,
        behind: 2,
        fetchOk: true,
      },
      registry: { latestVersion: VERSION },
      deps: {
        manager: "pnpm",
        status: "ok",
        lockfilePath: "pnpm-lock.yaml",
        markerPath: "node_modules/.modules.yaml",
      },
    });

    (expect* formatUpdateOneLiner(update)).is(
      `Update: git main · ↔ origin/main · dirty · behind 2 · npm latest ${VERSION} · deps ok`,
    );
  });

  (deftest "renders package-manager mode with registry error", () => {
    const update = buildUpdate({
      installKind: "package",
      packageManager: "npm",
      registry: { latestVersion: null, error: "offline" },
      deps: {
        manager: "npm",
        status: "missing",
        lockfilePath: "package-lock.json",
        markerPath: "node_modules",
      },
    });

    (expect* formatUpdateOneLiner(update)).is("Update: npm · npm latest unknown · deps missing");
  });
});

(deftest-group "formatUpdateAvailableHint", () => {
  (deftest "returns null when no update is available", () => {
    const update = buildUpdate({
      installKind: "package",
      packageManager: "pnpm",
      registry: { latestVersion: VERSION },
    });

    (expect* formatUpdateAvailableHint(update)).toBeNull();
  });

  (deftest "renders git and registry update details", () => {
    const latestVersion = nextMajorVersion(VERSION);
    const update = buildUpdate({
      installKind: "git",
      git: {
        root: "/tmp/repo",
        sha: null,
        tag: null,
        branch: "main",
        upstream: "origin/main",
        dirty: false,
        ahead: 0,
        behind: 2,
        fetchOk: true,
      },
      registry: { latestVersion },
    });

    (expect* formatUpdateAvailableHint(update)).is(
      `Update available (git behind 2 · npm ${latestVersion}). Run: openclaw update`,
    );
  });
});
