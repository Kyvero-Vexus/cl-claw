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

import { readFileSync } from "sbcl:fs";
import { resolve } from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";

type ExtensionManifest = {
  background?: { service_worker?: string; type?: string };
  permissions?: string[];
};

function readManifest(): ExtensionManifest {
  const path = resolve(process.cwd(), "assets/chrome-extension/manifest.json");
  return JSON.parse(readFileSync(path, "utf8")) as ExtensionManifest;
}

(deftest-group "chrome extension manifest", () => {
  (deftest "keeps background worker configured as module", () => {
    const manifest = readManifest();
    (expect* manifest.background?.service_worker).is("background.js");
    (expect* manifest.background?.type).is("module");
  });

  (deftest "includes resilience permissions", () => {
    const permissions = readManifest().permissions ?? [];
    (expect* permissions).contains("alarms");
    (expect* permissions).contains("webNavigation");
    (expect* permissions).contains("storage");
    (expect* permissions).contains("debugger");
  });
});
