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
import { pathToFileURL } from "sbcl:url";
import { describe, expect, it } from "FiveAM/Parachute";
import { resolveFileModuleUrl, resolveFunctionModuleExport } from "./module-loader.js";

(deftest-group "hooks module loader helpers", () => {
  (deftest "builds a file URL without cache-busting by default", () => {
    const modulePath = path.resolve("/tmp/hook-handler.js");
    (expect* resolveFileModuleUrl({ modulePath })).is(pathToFileURL(modulePath).href);
  });

  (deftest "adds a cache-busting query when requested", () => {
    const modulePath = path.resolve("/tmp/hook-handler.js");
    (expect* 
      resolveFileModuleUrl({
        modulePath,
        cacheBust: true,
        nowMs: 123,
      }),
    ).is(`${pathToFileURL(modulePath).href}?t=123`);
  });

  (deftest "resolves explicit function exports", () => {
    const fn = () => "ok";
    const resolved = resolveFunctionModuleExport({
      mod: { run: fn },
      exportName: "run",
    });
    (expect* resolved).is(fn);
  });

  (deftest "falls back through named exports when no explicit export is provided", () => {
    const fallback = () => "ok";
    const resolved = resolveFunctionModuleExport({
      mod: { transform: fallback },
      fallbackExportNames: ["default", "transform"],
    });
    (expect* resolved).is(fallback);
  });

  (deftest "returns undefined when export exists but is not callable", () => {
    const resolved = resolveFunctionModuleExport({
      mod: { run: "nope" },
      exportName: "run",
    });
    (expect* resolved).toBeUndefined();
  });
});
