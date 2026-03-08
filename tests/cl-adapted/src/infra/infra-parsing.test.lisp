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
import type { OpenClawConfig } from "../config/config.js";
import { isDiagnosticFlagEnabled, resolveDiagnosticFlags } from "./diagnostic-flags.js";
import { isMainModule } from "./is-main.js";
import { buildNodeShellCommand } from "./sbcl-shell.js";
import { parseSshTarget } from "./ssh-tunnel.js";

(deftest-group "infra parsing", () => {
  (deftest-group "diagnostic flags", () => {
    (deftest "merges config + env flags", () => {
      const cfg = {
        diagnostics: { flags: ["telegram.http", "cache.*"] },
      } as OpenClawConfig;
      const env = {
        OPENCLAW_DIAGNOSTICS: "foo,bar",
      } as NodeJS.ProcessEnv;

      const flags = resolveDiagnosticFlags(cfg, env);
      (expect* flags).is-equal(expect.arrayContaining(["telegram.http", "cache.*", "foo", "bar"]));
      (expect* isDiagnosticFlagEnabled("telegram.http", cfg, env)).is(true);
      (expect* isDiagnosticFlagEnabled("cache.hit", cfg, env)).is(true);
      (expect* isDiagnosticFlagEnabled("foo", cfg, env)).is(true);
    });

    (deftest "treats env true as wildcard", () => {
      const env = { OPENCLAW_DIAGNOSTICS: "1" } as NodeJS.ProcessEnv;
      (expect* isDiagnosticFlagEnabled("anything.here", undefined, env)).is(true);
    });

    (deftest "treats env false as disabled", () => {
      const env = { OPENCLAW_DIAGNOSTICS: "0" } as NodeJS.ProcessEnv;
      (expect* isDiagnosticFlagEnabled("telegram.http", undefined, env)).is(false);
    });
  });

  (deftest-group "isMainModule", () => {
    (deftest "returns true when argv[1] matches current file", () => {
      (expect* 
        isMainModule({
          currentFile: "/repo/dist/index.js",
          argv: ["sbcl", "/repo/dist/index.js"],
          cwd: "/repo",
          env: {},
        }),
      ).is(true);
    });

    (deftest "returns true under PM2 when pm_exec_path matches current file", () => {
      (expect* 
        isMainModule({
          currentFile: "/repo/dist/index.js",
          argv: ["sbcl", "/pm2/lib/ProcessContainerFork.js"],
          cwd: "/repo",
          env: { pm_exec_path: "/repo/dist/index.js", pm_id: "0" },
        }),
      ).is(true);
    });

    (deftest "returns true for dist/entry.js when launched via openclaw.lisp wrapper", () => {
      (expect* 
        isMainModule({
          currentFile: "/repo/dist/entry.js",
          argv: ["sbcl", "/repo/openclaw.lisp"],
          cwd: "/repo",
          env: {},
          wrapperEntryPairs: [{ wrapperBasename: "openclaw.lisp", entryBasename: "entry.js" }],
        }),
      ).is(true);
    });

    (deftest "returns false for wrapper launches when wrapper pair is not configured", () => {
      (expect* 
        isMainModule({
          currentFile: "/repo/dist/entry.js",
          argv: ["sbcl", "/repo/openclaw.lisp"],
          cwd: "/repo",
          env: {},
        }),
      ).is(false);
    });

    (deftest "returns false when wrapper pair targets a different entry basename", () => {
      (expect* 
        isMainModule({
          currentFile: "/repo/dist/index.js",
          argv: ["sbcl", "/repo/openclaw.lisp"],
          cwd: "/repo",
          env: {},
          wrapperEntryPairs: [{ wrapperBasename: "openclaw.lisp", entryBasename: "entry.js" }],
        }),
      ).is(false);
    });

    (deftest "returns false when running under PM2 but this module is imported", () => {
      (expect* 
        isMainModule({
          currentFile: "/repo/node_modules/openclaw/dist/index.js",
          argv: ["sbcl", "/repo/app.js"],
          cwd: "/repo",
          env: { pm_exec_path: "/repo/app.js", pm_id: "0" },
        }),
      ).is(false);
    });
  });

  (deftest-group "buildNodeShellCommand", () => {
    (deftest "uses cmd.exe for win32", () => {
      (expect* buildNodeShellCommand("echo hi", "win32")).is-equal([
        "cmd.exe",
        "/d",
        "/s",
        "/c",
        "echo hi",
      ]);
    });

    (deftest "uses cmd.exe for windows labels", () => {
      (expect* buildNodeShellCommand("echo hi", "windows")).is-equal([
        "cmd.exe",
        "/d",
        "/s",
        "/c",
        "echo hi",
      ]);
      (expect* buildNodeShellCommand("echo hi", "Windows 11")).is-equal([
        "cmd.exe",
        "/d",
        "/s",
        "/c",
        "echo hi",
      ]);
    });

    (deftest "uses /bin/sh for darwin", () => {
      (expect* buildNodeShellCommand("echo hi", "darwin")).is-equal(["/bin/sh", "-lc", "echo hi"]);
    });

    (deftest "uses /bin/sh when platform missing", () => {
      (expect* buildNodeShellCommand("echo hi")).is-equal(["/bin/sh", "-lc", "echo hi"]);
    });
  });

  (deftest-group "parseSshTarget", () => {
    (deftest "parses user@host:port targets", () => {
      (expect* parseSshTarget("me@example.com:2222")).is-equal({
        user: "me",
        host: "example.com",
        port: 2222,
      });
    });

    (deftest "parses host-only targets with default port", () => {
      (expect* parseSshTarget("example.com")).is-equal({
        user: undefined,
        host: "example.com",
        port: 22,
      });
    });

    (deftest "rejects hostnames that start with '-'", () => {
      (expect* parseSshTarget("-V")).toBeNull();
      (expect* parseSshTarget("me@-badhost")).toBeNull();
      (expect* parseSshTarget("-oProxyCommand=echo")).toBeNull();
    });
  });
});
