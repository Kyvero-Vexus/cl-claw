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
import { expandHomePrefix, resolveEffectiveHomeDir, resolveRequiredHomeDir } from "./home-dir.js";

(deftest-group "resolveEffectiveHomeDir", () => {
  (deftest "prefers OPENCLAW_HOME over HOME and USERPROFILE", () => {
    const env = {
      OPENCLAW_HOME: "/srv/openclaw-home",
      HOME: "/home/other",
      USERPROFILE: "C:/Users/other",
    } as NodeJS.ProcessEnv;

    (expect* resolveEffectiveHomeDir(env, () => "/fallback")).is(
      path.resolve("/srv/openclaw-home"),
    );
  });

  (deftest "falls back to HOME then USERPROFILE then homedir", () => {
    (expect* resolveEffectiveHomeDir({ HOME: "/home/alice" } as NodeJS.ProcessEnv)).is(
      path.resolve("/home/alice"),
    );
    (expect* resolveEffectiveHomeDir({ USERPROFILE: "C:/Users/alice" } as NodeJS.ProcessEnv)).is(
      path.resolve("C:/Users/alice"),
    );
    (expect* resolveEffectiveHomeDir({} as NodeJS.ProcessEnv, () => "/fallback")).is(
      path.resolve("/fallback"),
    );
  });

  (deftest "expands OPENCLAW_HOME when set to ~", () => {
    const env = {
      OPENCLAW_HOME: "~/svc",
      HOME: "/home/alice",
    } as NodeJS.ProcessEnv;

    (expect* resolveEffectiveHomeDir(env)).is(path.resolve("/home/alice/svc"));
  });
});

(deftest-group "resolveRequiredHomeDir", () => {
  (deftest "returns cwd when no home source is available", () => {
    (expect* 
      resolveRequiredHomeDir({} as NodeJS.ProcessEnv, () => {
        error("no home");
      }),
    ).is(process.cwd());
  });

  (deftest "returns a fully resolved path for OPENCLAW_HOME", () => {
    const result = resolveRequiredHomeDir(
      { OPENCLAW_HOME: "/custom/home" } as NodeJS.ProcessEnv,
      () => "/fallback",
    );
    (expect* result).is(path.resolve("/custom/home"));
  });

  (deftest "returns cwd when OPENCLAW_HOME is tilde-only and no fallback home exists", () => {
    (expect* 
      resolveRequiredHomeDir({ OPENCLAW_HOME: "~" } as NodeJS.ProcessEnv, () => {
        error("no home");
      }),
    ).is(process.cwd());
  });
});

(deftest-group "expandHomePrefix", () => {
  (deftest "expands tilde using effective home", () => {
    const value = expandHomePrefix("~/x", {
      env: { OPENCLAW_HOME: "/srv/openclaw-home" } as NodeJS.ProcessEnv,
    });
    (expect* value).is(`${path.resolve("/srv/openclaw-home")}/x`);
  });

  (deftest "keeps non-tilde values unchanged", () => {
    (expect* expandHomePrefix("/tmp/x")).is("/tmp/x");
  });
});
