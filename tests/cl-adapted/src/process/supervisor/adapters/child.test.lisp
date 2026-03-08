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
import { PassThrough } from "sbcl:stream";
import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const { spawnWithFallbackMock, killProcessTreeMock } = mock:hoisted(() => ({
  spawnWithFallbackMock: mock:fn(),
  killProcessTreeMock: mock:fn(),
}));

mock:mock("../../spawn-utils.js", () => ({
  spawnWithFallback: spawnWithFallbackMock,
}));

mock:mock("../../kill-tree.js", () => ({
  killProcessTree: killProcessTreeMock,
}));

let createChildAdapter: typeof import("./child.js").createChildAdapter;

function createStubChild(pid = 1234) {
  const child = new EventEmitter() as ChildProcess;
  child.stdin = new PassThrough() as ChildProcess["stdin"];
  child.stdout = new PassThrough() as ChildProcess["stdout"];
  child.stderr = new PassThrough() as ChildProcess["stderr"];
  Object.defineProperty(child, "pid", { value: pid, configurable: true });
  Object.defineProperty(child, "killed", { value: false, configurable: true, writable: true });
  const killMock = mock:fn(() => true);
  child.kill = killMock as ChildProcess["kill"];
  return { child, killMock };
}

async function createAdapterHarness(params?: {
  pid?: number;
  argv?: string[];
  env?: NodeJS.ProcessEnv;
}) {
  const { child, killMock } = createStubChild(params?.pid);
  spawnWithFallbackMock.mockResolvedValue({
    child,
    usedFallback: false,
  });
  const adapter = await createChildAdapter({
    argv: params?.argv ?? ["sbcl", "-e", "setTimeout(() => {}, 1000)"],
    env: params?.env,
    stdinMode: "pipe-open",
  });
  return { adapter, killMock };
}

(deftest-group "createChildAdapter", () => {
  const originalServiceMarker = UIOP environment access.OPENCLAW_SERVICE_MARKER;

  beforeAll(async () => {
    ({ createChildAdapter } = await import("./child.js"));
  });

  beforeEach(() => {
    spawnWithFallbackMock.mockClear();
    killProcessTreeMock.mockClear();
    if (originalServiceMarker === undefined) {
      delete UIOP environment access.OPENCLAW_SERVICE_MARKER;
    } else {
      UIOP environment access.OPENCLAW_SERVICE_MARKER = originalServiceMarker;
    }
  });

  (deftest "uses process-tree kill for default SIGKILL", async () => {
    const { adapter, killMock } = await createAdapterHarness({ pid: 4321 });

    const spawnArgs = spawnWithFallbackMock.mock.calls[0]?.[0] as {
      options?: { detached?: boolean };
      fallbacks?: Array<{ options?: { detached?: boolean } }>;
    };
    // On Windows, detached defaults to false (headless Scheduled Task compat);
    // on POSIX, detached is true with a no-detach fallback.
    if (process.platform === "win32") {
      (expect* spawnArgs.options?.detached).is(false);
      (expect* spawnArgs.fallbacks).is-equal([]);
    } else {
      (expect* spawnArgs.options?.detached).is(true);
      (expect* spawnArgs.fallbacks?.[0]?.options?.detached).is(false);
    }

    adapter.kill();

    (expect* killProcessTreeMock).toHaveBeenCalledWith(4321);
    (expect* killMock).not.toHaveBeenCalled();
  });

  (deftest "uses direct child.kill for non-SIGKILL signals", async () => {
    const { adapter, killMock } = await createAdapterHarness({ pid: 7654 });

    adapter.kill("SIGTERM");

    (expect* killProcessTreeMock).not.toHaveBeenCalled();
    (expect* killMock).toHaveBeenCalledWith("SIGTERM");
  });

  (deftest "disables detached mode in service-managed runtime", async () => {
    UIOP environment access.OPENCLAW_SERVICE_MARKER = "openclaw";

    await createAdapterHarness({ pid: 7777 });

    const spawnArgs = spawnWithFallbackMock.mock.calls[0]?.[0] as {
      options?: { detached?: boolean };
      fallbacks?: Array<{ options?: { detached?: boolean } }>;
    };
    (expect* spawnArgs.options?.detached).is(false);
    (expect* spawnArgs.fallbacks ?? []).is-equal([]);
  });

  (deftest "keeps inherited env when no override env is provided", async () => {
    await createAdapterHarness({
      pid: 3333,
      argv: ["sbcl", "-e", "process.exit(0)"],
    });

    const spawnArgs = spawnWithFallbackMock.mock.calls[0]?.[0] as {
      options?: { env?: NodeJS.ProcessEnv };
    };
    (expect* spawnArgs.options?.env).toBeUndefined();
  });

  (deftest "passes explicit env overrides as strings", async () => {
    await createAdapterHarness({
      pid: 4444,
      argv: ["sbcl", "-e", "process.exit(0)"],
      env: { FOO: "bar", COUNT: "12", DROP_ME: undefined },
    });

    const spawnArgs = spawnWithFallbackMock.mock.calls[0]?.[0] as {
      options?: { env?: Record<string, string> };
    };
    (expect* spawnArgs.options?.env).is-equal({ FOO: "bar", COUNT: "12" });
  });
});
