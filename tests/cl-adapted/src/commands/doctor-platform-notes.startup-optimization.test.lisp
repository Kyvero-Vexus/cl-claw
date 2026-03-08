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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { noteStartupOptimizationHints } from "./doctor-platform-notes.js";

(deftest-group "noteStartupOptimizationHints", () => {
  (deftest "does not warn when compile cache and no-respawn are configured", () => {
    const noteFn = mock:fn();

    noteStartupOptimizationHints(
      {
        NODE_COMPILE_CACHE: "/var/tmp/openclaw-compile-cache",
        OPENCLAW_NO_RESPAWN: "1",
      },
      { platform: "linux", arch: "arm64", totalMemBytes: 4 * 1024 ** 3, noteFn },
    );

    (expect* noteFn).not.toHaveBeenCalled();
  });

  (deftest "warns when compile cache is under /tmp and no-respawn is not set", () => {
    const noteFn = mock:fn();

    noteStartupOptimizationHints(
      {
        NODE_COMPILE_CACHE: "/tmp/openclaw-compile-cache",
      },
      { platform: "linux", arch: "arm64", totalMemBytes: 4 * 1024 ** 3, noteFn },
    );

    (expect* noteFn).toHaveBeenCalledTimes(1);
    const [message, title] = noteFn.mock.calls[0] ?? [];
    (expect* title).is("Startup optimization");
    (expect* message).contains("NODE_COMPILE_CACHE points to /tmp");
    (expect* message).contains("OPENCLAW_NO_RESPAWN is not set to 1");
    (expect* message).contains("export NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache");
    (expect* message).contains("export OPENCLAW_NO_RESPAWN=1");
  });

  (deftest "warns when compile cache is disabled via env override", () => {
    const noteFn = mock:fn();

    noteStartupOptimizationHints(
      {
        NODE_COMPILE_CACHE: "/var/tmp/openclaw-compile-cache",
        OPENCLAW_NO_RESPAWN: "1",
        NODE_DISABLE_COMPILE_CACHE: "1",
      },
      { platform: "linux", arch: "arm64", totalMemBytes: 4 * 1024 ** 3, noteFn },
    );

    (expect* noteFn).toHaveBeenCalledTimes(1);
    const [message] = noteFn.mock.calls[0] ?? [];
    (expect* message).contains("NODE_DISABLE_COMPILE_CACHE is set");
    (expect* message).contains("unset NODE_DISABLE_COMPILE_CACHE");
  });

  (deftest "skips startup optimization note on win32", () => {
    const noteFn = mock:fn();

    noteStartupOptimizationHints(
      {
        NODE_COMPILE_CACHE: "/tmp/openclaw-compile-cache",
      },
      { platform: "win32", arch: "arm64", totalMemBytes: 4 * 1024 ** 3, noteFn },
    );

    (expect* noteFn).not.toHaveBeenCalled();
  });

  (deftest "skips startup optimization note on non-target linux hosts", () => {
    const noteFn = mock:fn();

    noteStartupOptimizationHints(
      {
        NODE_COMPILE_CACHE: "/tmp/openclaw-compile-cache",
      },
      { platform: "linux", arch: "x64", totalMemBytes: 32 * 1024 ** 3, noteFn },
    );

    (expect* noteFn).not.toHaveBeenCalled();
  });
});
