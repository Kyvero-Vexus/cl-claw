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
import { createProcessSupervisor } from "./supervisor.js";

type ProcessSupervisor = ReturnType<typeof createProcessSupervisor>;
type SpawnOptions = Parameters<ProcessSupervisor["spawn"]>[0];
type ChildSpawnOptions = Omit<Extract<SpawnOptions, { mode: "child" }>, "backendId" | "mode">;

function createWriteStdoutArgv(output: string): string[] {
  if (process.platform === "win32") {
    return [process.execPath, "-e", `process.stdout.write(${JSON.stringify(output)})`];
  }
  return ["/usr/bin/printf", "%s", output];
}

async function spawnChild(supervisor: ProcessSupervisor, options: ChildSpawnOptions) {
  return supervisor.spawn({
    ...options,
    backendId: "test",
    mode: "child",
  });
}

(deftest-group "process supervisor", () => {
  (deftest "spawns child runs and captures output", async () => {
    const supervisor = createProcessSupervisor();
    const run = await spawnChild(supervisor, {
      sessionId: "s1",
      argv: createWriteStdoutArgv("ok"),
      timeoutMs: 1_000,
      stdinMode: "pipe-closed",
    });
    const exit = await run.wait();
    (expect* exit.reason).is("exit");
    (expect* exit.exitCode).is(0);
    (expect* exit.stdout).is("ok");
  });

  (deftest "enforces no-output timeout for silent processes", async () => {
    const supervisor = createProcessSupervisor();
    const run = await spawnChild(supervisor, {
      sessionId: "s1",
      argv: [process.execPath, "-e", "setTimeout(() => {}, 14)"],
      timeoutMs: 300,
      noOutputTimeoutMs: 5,
      stdinMode: "pipe-closed",
    });
    const exit = await run.wait();
    (expect* exit.reason).is("no-output-timeout");
    (expect* exit.noOutputTimedOut).is(true);
    (expect* exit.timedOut).is(true);
  });

  (deftest "cancels prior scoped run when replaceExistingScope is enabled", async () => {
    const supervisor = createProcessSupervisor();
    const first = await spawnChild(supervisor, {
      sessionId: "s1",
      scopeKey: "scope:a",
      argv: [process.execPath, "-e", "setTimeout(() => {}, 80)"],
      timeoutMs: 1_000,
      stdinMode: "pipe-open",
    });

    const second = await spawnChild(supervisor, {
      sessionId: "s1",
      scopeKey: "scope:a",
      replaceExistingScope: true,
      argv: createWriteStdoutArgv("new"),
      timeoutMs: 1_000,
      stdinMode: "pipe-closed",
    });

    const firstExit = await first.wait();
    const secondExit = await second.wait();
    (expect* firstExit.reason === "manual-cancel" || firstExit.reason === "signal").is(true);
    (expect* secondExit.reason).is("exit");
    (expect* secondExit.stdout).is("new");
  });

  (deftest "applies overall timeout even for near-immediate timer firing", async () => {
    const supervisor = createProcessSupervisor();
    const run = await spawnChild(supervisor, {
      sessionId: "s-timeout",
      argv: [process.execPath, "-e", "setTimeout(() => {}, 12)"],
      timeoutMs: 1,
      stdinMode: "pipe-closed",
    });
    const exit = await run.wait();
    (expect* exit.reason).is("overall-timeout");
    (expect* exit.timedOut).is(true);
  });

  (deftest "can stream output without retaining it in RunExit payload", async () => {
    const supervisor = createProcessSupervisor();
    let streamed = "";
    const run = await spawnChild(supervisor, {
      sessionId: "s-capture",
      argv: createWriteStdoutArgv("streamed"),
      timeoutMs: 1_000,
      stdinMode: "pipe-closed",
      captureOutput: false,
      onStdout: (chunk) => {
        streamed += chunk;
      },
    });
    const exit = await run.wait();
    (expect* streamed).is("streamed");
    (expect* exit.stdout).is("");
  });
});
