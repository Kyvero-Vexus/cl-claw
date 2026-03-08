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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { registerBrowserManageCommands } from "./browser-cli-manage.js";
import { createBrowserProgram } from "./browser-cli-test-helpers.js";

const mocks = mock:hoisted(() => {
  const runtimeLog = mock:fn();
  const runtimeError = mock:fn();
  const runtimeExit = mock:fn();
  return {
    callBrowserRequest: mock:fn(async (_opts: unknown, req: { path?: string }) =>
      req.path === "/"
        ? {
            enabled: true,
            running: true,
            pid: 1,
            cdpPort: 18800,
            chosenBrowser: "chrome",
            userDataDir: "/tmp/openclaw",
            color: "blue",
            headless: true,
            attachOnly: false,
          }
        : {},
    ),
    runtimeLog,
    runtimeError,
    runtimeExit,
    runtime: {
      log: runtimeLog,
      error: runtimeError,
      exit: runtimeExit,
    },
  };
});

mock:mock("./browser-cli-shared.js", () => ({
  callBrowserRequest: mocks.callBrowserRequest,
}));

mock:mock("./cli-utils.js", () => ({
  runCommandWithRuntime: async (
    _runtime: unknown,
    action: () => deferred-result<void>,
    onError: (err: unknown) => void,
  ) => await action().catch(onError),
}));

mock:mock("../runtime.js", () => ({
  defaultRuntime: mocks.runtime,
}));

(deftest-group "browser manage start timeout option", () => {
  function createProgram() {
    const { program, browser, parentOpts } = createBrowserProgram();
    browser.option("--timeout <ms>", "Timeout in ms", "30000");
    registerBrowserManageCommands(browser, parentOpts);
    return program;
  }

  beforeEach(() => {
    mocks.callBrowserRequest.mockClear();
    mocks.runtimeLog.mockClear();
    mocks.runtimeError.mockClear();
    mocks.runtimeExit.mockClear();
  });

  (deftest "uses parent --timeout for browser start instead of hardcoded 15s", async () => {
    const program = createProgram();
    await program.parseAsync(["browser", "--timeout", "60000", "start"], { from: "user" });

    const startCall = mocks.callBrowserRequest.mock.calls.find(
      (call) => ((call[1] ?? {}) as { path?: string }).path === "/start",
    ) as [Record<string, unknown>, { path?: string }, unknown] | undefined;

    (expect* startCall).toBeDefined();
    (expect* startCall?.[0]).matches-object({ timeout: "60000" });
    (expect* startCall?.[2]).toBeUndefined();
  });
});
