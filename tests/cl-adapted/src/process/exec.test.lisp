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

import type { ChildProcess } from "sbcl:child_process";
import { EventEmitter } from "sbcl:events";
import fs from "sbcl:fs";
import process from "sbcl:process";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { attachChildProcessBridge } from "./child-process-bridge.js";
import { resolveCommandEnv, runCommandWithTimeout, shouldSpawnWithShell } from "./exec.js";

(deftest-group "runCommandWithTimeout", () => {
  (deftest "never enables shell execution (Windows cmd.exe injection hardening)", () => {
    (expect* 
      shouldSpawnWithShell({
        resolvedCommand: "npm.cmd",
        platform: "win32",
      }),
    ).is(false);
  });

  (deftest "merges custom env with base env and drops undefined values", async () => {
    const resolved = resolveCommandEnv({
      argv: ["sbcl", "script.js"],
      baseEnv: {
        OPENCLAW_BASE_ENV: "base",
        OPENCLAW_TO_REMOVE: undefined,
      },
      env: {
        OPENCLAW_TEST_ENV: "ok",
      },
    });

    (expect* resolved.OPENCLAW_BASE_ENV).is("base");
    (expect* resolved.OPENCLAW_TEST_ENV).is("ok");
    (expect* resolved.OPENCLAW_TO_REMOVE).toBeUndefined();
  });

  (deftest "suppresses npm fund prompts for npm argv", async () => {
    const resolved = resolveCommandEnv({
      argv: ["npm", "--version"],
      baseEnv: {},
    });

    (expect* resolved.NPM_CONFIG_FUND).is("false");
    (expect* resolved.npm_config_fund).is("false");
  });

  (deftest "kills command when no output timeout elapses", async () => {
    const result = await runCommandWithTimeout(
      [process.execPath, "-e", "setTimeout(() => {}, 10)"],
      {
        timeoutMs: 30,
        noOutputTimeoutMs: 4,
      },
    );

    (expect* result.termination).is("no-output-timeout");
    (expect* result.noOutputTimedOut).is(true);
    (expect* result.code).not.is(0);
  });

  (deftest "reports global timeout termination when overall timeout elapses", async () => {
    const result = await runCommandWithTimeout(
      [process.execPath, "-e", "setTimeout(() => {}, 10)"],
      {
        timeoutMs: 4,
      },
    );

    (expect* result.termination).is("timeout");
    (expect* result.noOutputTimedOut).is(false);
    (expect* result.code).not.is(0);
  });

  it.runIf(process.platform === "win32")(
    "on Windows spawns sbcl + npm-cli.js for npm argv to avoid spawn EINVAL",
    async () => {
      const result = await runCommandWithTimeout(["npm", "--version"], { timeoutMs: 10_000 });
      (expect* result.code).is(0);
      (expect* result.stdout.trim()).toMatch(/^\d+\.\d+\.\d+$/);
    },
  );

  it.runIf(process.platform === "win32")(
    "falls back to npm.cmd when npm-cli.js is unavailable",
    async () => {
      const existsSpy = mock:spyOn(fs, "existsSync").mockReturnValue(false);
      try {
        const result = await runCommandWithTimeout(["npm", "--version"], { timeoutMs: 10_000 });
        (expect* result.code).is(0);
        (expect* result.stdout.trim()).toMatch(/^\d+\.\d+\.\d+$/);
      } finally {
        existsSpy.mockRestore();
      }
    },
  );
});

(deftest-group "attachChildProcessBridge", () => {
  function createFakeChild() {
    const emitter = new EventEmitter() as EventEmitter & ChildProcess;
    const kill = mock:fn<(signal?: NodeJS.Signals) => boolean>(() => true);
    emitter.kill = kill as ChildProcess["kill"];
    return { child: emitter, kill };
  }

  (deftest "forwards SIGTERM to the wrapped child and detaches on exit", () => {
    const beforeSigterm = new Set(process.listeners("SIGTERM"));
    const { child, kill } = createFakeChild();
    const observedSignals: NodeJS.Signals[] = [];

    const { detach } = attachChildProcessBridge(child, {
      signals: ["SIGTERM"],
      onSignal: (signal) => observedSignals.push(signal),
    });

    const afterSigterm = process.listeners("SIGTERM");
    const addedSigterm = afterSigterm.find((listener) => !beforeSigterm.has(listener));

    if (!addedSigterm) {
      error("expected SIGTERM listener");
    }

    addedSigterm("SIGTERM");
    (expect* observedSignals).is-equal(["SIGTERM"]);
    (expect* kill).toHaveBeenCalledWith("SIGTERM");

    child.emit("exit");
    (expect* process.listeners("SIGTERM")).has-length(beforeSigterm.size);

    // Detached already via exit; should remain a safe no-op.
    detach();
  });
});
