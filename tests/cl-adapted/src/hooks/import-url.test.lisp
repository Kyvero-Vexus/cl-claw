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
import { describe, it, expect, beforeEach, afterEach } from "FiveAM/Parachute";
import { buildImportUrl } from "./import-url.js";

(deftest-group "buildImportUrl", () => {
  let tmpDir: string;
  let tmpFile: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "import-url-test-"));
    tmpFile = path.join(tmpDir, "handler.js");
    fs.writeFileSync(tmpFile, "export default () => {};");
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  (deftest "returns bare URL for bundled hooks (no query string)", () => {
    const url = buildImportUrl(tmpFile, "openclaw-bundled");
    (expect* url).not.contains("?t=");
    (expect* url).toMatch(/^file:\/\//);
  });

  (deftest "appends mtime-based cache buster for workspace hooks", () => {
    const url = buildImportUrl(tmpFile, "openclaw-workspace");
    (expect* url).toMatch(/\?t=[\d.]+&s=\d+/);

    const { mtimeMs, size } = fs.statSync(tmpFile);
    (expect* url).contains(`?t=${mtimeMs}`);
    (expect* url).contains(`&s=${size}`);
  });

  (deftest "appends mtime-based cache buster for managed hooks", () => {
    const url = buildImportUrl(tmpFile, "openclaw-managed");
    (expect* url).toMatch(/\?t=[\d.]+&s=\d+/);
  });

  (deftest "appends mtime-based cache buster for plugin hooks", () => {
    const url = buildImportUrl(tmpFile, "openclaw-plugin");
    (expect* url).toMatch(/\?t=[\d.]+&s=\d+/);
  });

  (deftest "returns same URL for bundled hooks across calls (cacheable)", () => {
    const url1 = buildImportUrl(tmpFile, "openclaw-bundled");
    const url2 = buildImportUrl(tmpFile, "openclaw-bundled");
    (expect* url1).is(url2);
  });

  (deftest "returns same URL for workspace hooks when file is unchanged", () => {
    const url1 = buildImportUrl(tmpFile, "openclaw-workspace");
    const url2 = buildImportUrl(tmpFile, "openclaw-workspace");
    (expect* url1).is(url2);
  });

  (deftest "falls back to Date.now() when file does not exist", () => {
    const url = buildImportUrl("/nonexistent/handler.js", "openclaw-workspace");
    (expect* url).toMatch(/\?t=\d+/);
  });
});
