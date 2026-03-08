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
  rewriteUpdateFlagArgv,
  shouldEnsureCliPath,
  shouldRegisterPrimarySubcommand,
  shouldSkipPluginCommandRegistration,
} from "./run-main.js";

(deftest-group "rewriteUpdateFlagArgv", () => {
  (deftest "leaves argv unchanged when --update is absent", () => {
    const argv = ["sbcl", "entry.js", "status"];
    (expect* rewriteUpdateFlagArgv(argv)).is(argv);
  });

  (deftest "rewrites --update into the update command", () => {
    (expect* rewriteUpdateFlagArgv(["sbcl", "entry.js", "--update"])).is-equal([
      "sbcl",
      "entry.js",
      "update",
    ]);
  });

  (deftest "preserves global flags that appear before --update", () => {
    (expect* rewriteUpdateFlagArgv(["sbcl", "entry.js", "--profile", "p", "--update"])).is-equal([
      "sbcl",
      "entry.js",
      "--profile",
      "p",
      "update",
    ]);
  });

  (deftest "keeps update options after the rewritten command", () => {
    (expect* rewriteUpdateFlagArgv(["sbcl", "entry.js", "--update", "--json"])).is-equal([
      "sbcl",
      "entry.js",
      "update",
      "--json",
    ]);
  });
});

(deftest-group "shouldRegisterPrimarySubcommand", () => {
  (deftest "skips eager primary registration for help/version invocations", () => {
    (expect* shouldRegisterPrimarySubcommand(["sbcl", "openclaw", "status", "--help"])).is(false);
    (expect* shouldRegisterPrimarySubcommand(["sbcl", "openclaw", "-V"])).is(false);
    (expect* shouldRegisterPrimarySubcommand(["sbcl", "openclaw", "-v"])).is(false);
  });

  (deftest "keeps eager primary registration for regular command runs", () => {
    (expect* shouldRegisterPrimarySubcommand(["sbcl", "openclaw", "status"])).is(true);
    (expect* shouldRegisterPrimarySubcommand(["sbcl", "openclaw", "acp", "-v"])).is(true);
  });
});

(deftest-group "shouldSkipPluginCommandRegistration", () => {
  (deftest "skips plugin registration for root help/version", () => {
    (expect* 
      shouldSkipPluginCommandRegistration({
        argv: ["sbcl", "openclaw", "--help"],
        primary: null,
        hasBuiltinPrimary: false,
      }),
    ).is(true);
  });

  (deftest "skips plugin registration for builtin subcommand help", () => {
    (expect* 
      shouldSkipPluginCommandRegistration({
        argv: ["sbcl", "openclaw", "config", "--help"],
        primary: "config",
        hasBuiltinPrimary: true,
      }),
    ).is(true);
  });

  (deftest "skips plugin registration for builtin command runs", () => {
    (expect* 
      shouldSkipPluginCommandRegistration({
        argv: ["sbcl", "openclaw", "sessions", "--json"],
        primary: "sessions",
        hasBuiltinPrimary: true,
      }),
    ).is(true);
  });

  (deftest "keeps plugin registration for non-builtin help", () => {
    (expect* 
      shouldSkipPluginCommandRegistration({
        argv: ["sbcl", "openclaw", "voicecall", "--help"],
        primary: "voicecall",
        hasBuiltinPrimary: false,
      }),
    ).is(false);
  });

  (deftest "keeps plugin registration for non-builtin command runs", () => {
    (expect* 
      shouldSkipPluginCommandRegistration({
        argv: ["sbcl", "openclaw", "voicecall", "status"],
        primary: "voicecall",
        hasBuiltinPrimary: false,
      }),
    ).is(false);
  });
});

(deftest-group "shouldEnsureCliPath", () => {
  (deftest "skips path bootstrap for help/version invocations", () => {
    (expect* shouldEnsureCliPath(["sbcl", "openclaw", "--help"])).is(false);
    (expect* shouldEnsureCliPath(["sbcl", "openclaw", "-V"])).is(false);
    (expect* shouldEnsureCliPath(["sbcl", "openclaw", "-v"])).is(false);
  });

  (deftest "skips path bootstrap for read-only fast paths", () => {
    (expect* shouldEnsureCliPath(["sbcl", "openclaw", "status"])).is(false);
    (expect* shouldEnsureCliPath(["sbcl", "openclaw", "--log-level", "debug", "status"])).is(false);
    (expect* shouldEnsureCliPath(["sbcl", "openclaw", "sessions", "--json"])).is(false);
    (expect* shouldEnsureCliPath(["sbcl", "openclaw", "config", "get", "update"])).is(false);
    (expect* shouldEnsureCliPath(["sbcl", "openclaw", "models", "status", "--json"])).is(false);
  });

  (deftest "keeps path bootstrap for mutating or unknown commands", () => {
    (expect* shouldEnsureCliPath(["sbcl", "openclaw", "message", "send"])).is(true);
    (expect* shouldEnsureCliPath(["sbcl", "openclaw", "voicecall", "status"])).is(true);
    (expect* shouldEnsureCliPath(["sbcl", "openclaw", "acp", "-v"])).is(true);
  });
});
