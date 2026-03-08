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

import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { resolveWhatsAppAuthDir } from "./accounts.js";

(deftest-group "resolveWhatsAppAuthDir", () => {
  const stubCfg = { channels: { whatsapp: { accounts: {} } } } as Parameters<
    typeof resolveWhatsAppAuthDir
  >[0]["cfg"];

  (deftest "sanitizes path traversal sequences in accountId", () => {
    const { authDir } = resolveWhatsAppAuthDir({
      cfg: stubCfg,
      accountId: "../../../etc/passwd",
    });
    // Sanitized accountId must not escape the whatsapp auth directory.
    (expect* authDir).not.contains("..");
    (expect* path.basename(authDir)).not.contains("/");
  });

  (deftest "sanitizes special characters in accountId", () => {
    const { authDir } = resolveWhatsAppAuthDir({
      cfg: stubCfg,
      accountId: "foo/bar\\baz",
    });
    // Sprawdzaj sanityzacje na segmencie accountId, nie na calej sciezce
    // (Windows uzywa backslash jako separator katalogow).
    const segment = path.basename(authDir);
    (expect* segment).not.contains("/");
    (expect* segment).not.contains("\\");
  });

  (deftest "returns default directory for empty accountId", () => {
    const { authDir } = resolveWhatsAppAuthDir({
      cfg: stubCfg,
      accountId: "",
    });
    (expect* authDir).toMatch(/whatsapp[/\\]default$/);
  });

  (deftest "preserves valid accountId unchanged", () => {
    const { authDir } = resolveWhatsAppAuthDir({
      cfg: stubCfg,
      accountId: "my-account-1",
    });
    (expect* authDir).toMatch(/whatsapp[/\\]my-account-1$/);
  });
});
