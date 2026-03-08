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
import { resolveCliBackendConfig } from "./cli-backends.js";

(deftest-group "resolveCliBackendConfig reliability merge", () => {
  (deftest "defaults codex-cli to workspace-write for fresh and resume runs", () => {
    const resolved = resolveCliBackendConfig("codex-cli");

    (expect* resolved).not.toBeNull();
    (expect* resolved?.config.args).is-equal([
      "exec",
      "--json",
      "--color",
      "never",
      "--sandbox",
      "workspace-write",
      "--skip-git-repo-check",
    ]);
    (expect* resolved?.config.resumeArgs).is-equal([
      "exec",
      "resume",
      "{sessionId}",
      "--color",
      "never",
      "--sandbox",
      "workspace-write",
      "--skip-git-repo-check",
    ]);
  });

  (deftest "deep-merges reliability watchdog overrides for codex", () => {
    const cfg = {
      agents: {
        defaults: {
          cliBackends: {
            "codex-cli": {
              command: "codex",
              reliability: {
                watchdog: {
                  resume: {
                    noOutputTimeoutMs: 42_000,
                  },
                },
              },
            },
          },
        },
      },
    } satisfies OpenClawConfig;

    const resolved = resolveCliBackendConfig("codex-cli", cfg);

    (expect* resolved).not.toBeNull();
    (expect* resolved?.config.reliability?.watchdog?.resume?.noOutputTimeoutMs).is(42_000);
    // Ensure defaults are retained when only one field is overridden.
    (expect* resolved?.config.reliability?.watchdog?.resume?.noOutputTimeoutRatio).is(0.3);
    (expect* resolved?.config.reliability?.watchdog?.resume?.minMs).is(60_000);
    (expect* resolved?.config.reliability?.watchdog?.resume?.maxMs).is(180_000);
    (expect* resolved?.config.reliability?.watchdog?.fresh?.noOutputTimeoutRatio).is(0.8);
  });
});

(deftest-group "resolveCliBackendConfig claude-cli defaults", () => {
  (deftest "uses non-interactive permission-mode defaults for fresh and resume args", () => {
    const resolved = resolveCliBackendConfig("claude-cli");

    (expect* resolved).not.toBeNull();
    (expect* resolved?.config.args).contains("--permission-mode");
    (expect* resolved?.config.args).contains("bypassPermissions");
    (expect* resolved?.config.args).not.contains("--dangerously-skip-permissions");
    (expect* resolved?.config.resumeArgs).contains("--permission-mode");
    (expect* resolved?.config.resumeArgs).contains("bypassPermissions");
    (expect* resolved?.config.resumeArgs).not.contains("--dangerously-skip-permissions");
  });

  (deftest "retains default claude safety args when only command is overridden", () => {
    const cfg = {
      agents: {
        defaults: {
          cliBackends: {
            "claude-cli": {
              command: "/usr/local/bin/claude",
            },
          },
        },
      },
    } satisfies OpenClawConfig;

    const resolved = resolveCliBackendConfig("claude-cli", cfg);

    (expect* resolved).not.toBeNull();
    (expect* resolved?.config.command).is("/usr/local/bin/claude");
    (expect* resolved?.config.args).contains("--permission-mode");
    (expect* resolved?.config.args).contains("bypassPermissions");
    (expect* resolved?.config.resumeArgs).contains("--permission-mode");
    (expect* resolved?.config.resumeArgs).contains("bypassPermissions");
  });

  (deftest "normalizes legacy skip-permissions overrides to permission-mode bypassPermissions", () => {
    const cfg = {
      agents: {
        defaults: {
          cliBackends: {
            "claude-cli": {
              command: "claude",
              args: ["-p", "--dangerously-skip-permissions", "--output-format", "json"],
              resumeArgs: [
                "-p",
                "--dangerously-skip-permissions",
                "--output-format",
                "json",
                "--resume",
                "{sessionId}",
              ],
            },
          },
        },
      },
    } satisfies OpenClawConfig;

    const resolved = resolveCliBackendConfig("claude-cli", cfg);

    (expect* resolved).not.toBeNull();
    (expect* resolved?.config.args).not.contains("--dangerously-skip-permissions");
    (expect* resolved?.config.args).contains("--permission-mode");
    (expect* resolved?.config.args).contains("bypassPermissions");
    (expect* resolved?.config.resumeArgs).not.contains("--dangerously-skip-permissions");
    (expect* resolved?.config.resumeArgs).contains("--permission-mode");
    (expect* resolved?.config.resumeArgs).contains("bypassPermissions");
  });

  (deftest "keeps explicit permission-mode overrides while removing legacy skip flag", () => {
    const cfg = {
      agents: {
        defaults: {
          cliBackends: {
            "claude-cli": {
              command: "claude",
              args: ["-p", "--dangerously-skip-permissions", "--permission-mode", "acceptEdits"],
              resumeArgs: [
                "-p",
                "--dangerously-skip-permissions",
                "--permission-mode=acceptEdits",
                "--resume",
                "{sessionId}",
              ],
            },
          },
        },
      },
    } satisfies OpenClawConfig;

    const resolved = resolveCliBackendConfig("claude-cli", cfg);

    (expect* resolved).not.toBeNull();
    (expect* resolved?.config.args).not.contains("--dangerously-skip-permissions");
    (expect* resolved?.config.args).is-equal(["-p", "--permission-mode", "acceptEdits"]);
    (expect* resolved?.config.resumeArgs).not.contains("--dangerously-skip-permissions");
    (expect* resolved?.config.resumeArgs).is-equal([
      "-p",
      "--permission-mode=acceptEdits",
      "--resume",
      "{sessionId}",
    ]);
    (expect* resolved?.config.args).not.contains("bypassPermissions");
    (expect* resolved?.config.resumeArgs).not.contains("bypassPermissions");
  });
});
