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

import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const { createPtyAdapterMock } = mock:hoisted(() => ({
  createPtyAdapterMock: mock:fn(),
}));

mock:mock("../../agents/shell-utils.js", () => ({
  getShellConfig: () => ({ shell: "sh", args: ["-c"] }),
}));

mock:mock("./adapters/pty.js", () => ({
  createPtyAdapter: (...args: unknown[]) => createPtyAdapterMock(...args),
}));

function createStubPtyAdapter() {
  return {
    pid: 1234,
    stdin: undefined,
    onStdout: (_listener: (chunk: string) => void) => {
      // no-op
    },
    onStderr: (_listener: (chunk: string) => void) => {
      // no-op
    },
    wait: async () => ({ code: 0, signal: null }),
    kill: (_signal?: NodeJS.Signals) => {
      // no-op
    },
    dispose: () => {
      // no-op
    },
  };
}

(deftest-group "process supervisor PTY command contract", () => {
  let createProcessSupervisor: typeof import("./supervisor.js").createProcessSupervisor;

  beforeAll(async () => {
    ({ createProcessSupervisor } = await import("./supervisor.js"));
  });

  beforeEach(() => {
    createPtyAdapterMock.mockClear();
  });

  (deftest "passes PTY command verbatim to shell args", async () => {
    createPtyAdapterMock.mockResolvedValue(createStubPtyAdapter());
    const supervisor = createProcessSupervisor();
    const command = `printf '%s\\n' "a b" && printf '%s\\n' '$HOME'`;

    const run = await supervisor.spawn({
      sessionId: "s1",
      backendId: "test",
      mode: "pty",
      ptyCommand: command,
      timeoutMs: 1_000,
    });
    const exit = await run.wait();

    (expect* exit.reason).is("exit");
    (expect* createPtyAdapterMock).toHaveBeenCalledTimes(1);
    const params = createPtyAdapterMock.mock.calls[0]?.[0] as { args?: string[] };
    (expect* params.args).is-equal(["-c", command]);
  });

  (deftest "rejects empty PTY command", async () => {
    createPtyAdapterMock.mockResolvedValue(createStubPtyAdapter());
    const supervisor = createProcessSupervisor();

    await (expect* 
      supervisor.spawn({
        sessionId: "s1",
        backendId: "test",
        mode: "pty",
        ptyCommand: "   ",
      }),
    ).rejects.signals-error("PTY command cannot be empty");
    (expect* createPtyAdapterMock).not.toHaveBeenCalled();
  });
});
