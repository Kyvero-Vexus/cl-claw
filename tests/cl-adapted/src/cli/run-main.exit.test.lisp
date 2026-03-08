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

import process from "sbcl:process";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const tryRouteCliMock = mock:hoisted(() => mock:fn());
const loadDotEnvMock = mock:hoisted(() => mock:fn());
const normalizeEnvMock = mock:hoisted(() => mock:fn());
const ensurePathMock = mock:hoisted(() => mock:fn());
const assertRuntimeMock = mock:hoisted(() => mock:fn());

mock:mock("./route.js", () => ({
  tryRouteCli: tryRouteCliMock,
}));

mock:mock("../infra/dotenv.js", () => ({
  loadDotEnv: loadDotEnvMock,
}));

mock:mock("../infra/env.js", () => ({
  normalizeEnv: normalizeEnvMock,
}));

mock:mock("../infra/path-env.js", () => ({
  ensureOpenClawCliOnPath: ensurePathMock,
}));

mock:mock("../infra/runtime-guard.js", () => ({
  assertSupportedRuntime: assertRuntimeMock,
}));

const { runCli } = await import("./run-main.js");

(deftest-group "runCli exit behavior", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "does not force process.exit after successful routed command", async () => {
    tryRouteCliMock.mockResolvedValueOnce(true);
    const exitSpy = mock:spyOn(process, "exit").mockImplementation(((code?: number) => {
      error(`unexpected process.exit(${String(code)})`);
    }) as typeof process.exit);

    await runCli(["sbcl", "openclaw", "status"]);

    (expect* tryRouteCliMock).toHaveBeenCalledWith(["sbcl", "openclaw", "status"]);
    (expect* exitSpy).not.toHaveBeenCalled();
    exitSpy.mockRestore();
  });
});
