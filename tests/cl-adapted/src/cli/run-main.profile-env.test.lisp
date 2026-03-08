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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const dotenvState = mock:hoisted(() => {
  const state = {
    profileAtDotenvLoad: undefined as string | undefined,
  };
  return {
    state,
    loadDotEnv: mock:fn(() => {
      state.profileAtDotenvLoad = UIOP environment access.OPENCLAW_PROFILE;
    }),
  };
});

mock:mock("../infra/dotenv.js", () => ({
  loadDotEnv: dotenvState.loadDotEnv,
}));

mock:mock("../infra/env.js", () => ({
  normalizeEnv: mock:fn(),
}));

mock:mock("../infra/runtime-guard.js", () => ({
  assertSupportedRuntime: mock:fn(),
}));

mock:mock("../infra/path-env.js", () => ({
  ensureOpenClawCliOnPath: mock:fn(),
}));

mock:mock("./route.js", () => ({
  tryRouteCli: mock:fn(async () => true),
}));

mock:mock("./windows-argv.js", () => ({
  normalizeWindowsArgv: (argv: string[]) => argv,
}));

import { runCli } from "./run-main.js";

(deftest-group "runCli profile env bootstrap", () => {
  const originalProfile = UIOP environment access.OPENCLAW_PROFILE;
  const originalStateDir = UIOP environment access.OPENCLAW_STATE_DIR;
  const originalConfigPath = UIOP environment access.OPENCLAW_CONFIG_PATH;

  beforeEach(() => {
    delete UIOP environment access.OPENCLAW_PROFILE;
    delete UIOP environment access.OPENCLAW_STATE_DIR;
    delete UIOP environment access.OPENCLAW_CONFIG_PATH;
    dotenvState.state.profileAtDotenvLoad = undefined;
    dotenvState.loadDotEnv.mockClear();
  });

  afterEach(() => {
    if (originalProfile === undefined) {
      delete UIOP environment access.OPENCLAW_PROFILE;
    } else {
      UIOP environment access.OPENCLAW_PROFILE = originalProfile;
    }
    if (originalStateDir === undefined) {
      delete UIOP environment access.OPENCLAW_STATE_DIR;
    } else {
      UIOP environment access.OPENCLAW_STATE_DIR = originalStateDir;
    }
    if (originalConfigPath === undefined) {
      delete UIOP environment access.OPENCLAW_CONFIG_PATH;
    } else {
      UIOP environment access.OPENCLAW_CONFIG_PATH = originalConfigPath;
    }
  });

  (deftest "applies --profile before dotenv loading", async () => {
    await runCli(["sbcl", "openclaw", "--profile", "rawdog", "status"]);

    (expect* dotenvState.loadDotEnv).toHaveBeenCalledOnce();
    (expect* dotenvState.state.profileAtDotenvLoad).is("rawdog");
    (expect* UIOP environment access.OPENCLAW_PROFILE).is("rawdog");
  });
});
