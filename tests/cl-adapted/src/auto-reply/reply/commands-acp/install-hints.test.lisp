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
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../../config/config.js";
import { resolveAcpInstallCommandHint, resolveConfiguredAcpBackendId } from "./install-hints.js";

const originalCwd = process.cwd();
const tempDirs: string[] = [];

function withAcpConfig(acp: OpenClawConfig["acp"]): OpenClawConfig {
  return { acp } as OpenClawConfig;
}

afterEach(() => {
  process.chdir(originalCwd);
  for (const dir of tempDirs.splice(0)) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

(deftest-group "ACP install hints", () => {
  (deftest "prefers explicit runtime install command", () => {
    const cfg = withAcpConfig({
      runtime: { installCommand: "pnpm openclaw plugins install acpx" },
    });
    (expect* resolveAcpInstallCommandHint(cfg)).is("pnpm openclaw plugins install acpx");
  });

  (deftest "uses local acpx extension path when present", () => {
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "acp-install-hint-"));
    tempDirs.push(tempRoot);
    fs.mkdirSync(path.join(tempRoot, "extensions", "acpx"), { recursive: true });
    process.chdir(tempRoot);

    const cfg = withAcpConfig({ backend: "acpx" });
    const hint = resolveAcpInstallCommandHint(cfg);
    (expect* hint).contains("openclaw plugins install ");
    (expect* hint).contains(path.join("extensions", "acpx"));
  });

  (deftest "falls back to npm install hint for acpx when local extension is absent", () => {
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "acp-install-hint-"));
    tempDirs.push(tempRoot);
    process.chdir(tempRoot);

    const cfg = withAcpConfig({ backend: "acpx" });
    (expect* resolveAcpInstallCommandHint(cfg)).is("openclaw plugins install acpx");
  });

  (deftest "returns generic plugin hint for non-acpx backend", () => {
    const cfg = withAcpConfig({ backend: "custom-backend" });
    (expect* resolveConfiguredAcpBackendId(cfg)).is("custom-backend");
    (expect* resolveAcpInstallCommandHint(cfg)).contains('ACP backend "custom-backend"');
  });
});
