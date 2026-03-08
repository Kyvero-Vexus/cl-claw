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

const selectMock = mock:hoisted(() => mock:fn());
const createSecretsConfigIOMock = mock:hoisted(() => mock:fn());
const readJsonObjectIfExistsMock = mock:hoisted(() => mock:fn());

mock:mock("@clack/prompts", () => ({
  confirm: mock:fn(),
  select: (...args: unknown[]) => selectMock(...args),
  text: mock:fn(),
}));

mock:mock("./config-io.js", () => ({
  createSecretsConfigIO: (...args: unknown[]) => createSecretsConfigIOMock(...args),
}));

mock:mock("./storage-scan.js", () => ({
  readJsonObjectIfExists: (...args: unknown[]) => readJsonObjectIfExistsMock(...args),
}));

const { runSecretsConfigureInteractive } = await import("./configure.js");

(deftest-group "runSecretsConfigureInteractive", () => {
  beforeEach(() => {
    selectMock.mockReset();
    createSecretsConfigIOMock.mockReset();
    readJsonObjectIfExistsMock.mockReset();
  });

  (deftest "does not load auth-profiles when running providers-only", async () => {
    Object.defineProperty(process.stdin, "isTTY", {
      value: true,
      configurable: true,
    });

    selectMock.mockResolvedValue("continue");
    createSecretsConfigIOMock.mockReturnValue({
      readConfigFileSnapshotForWrite: async () => ({
        snapshot: {
          valid: true,
          config: {},
          resolved: {},
        },
      }),
    });
    readJsonObjectIfExistsMock.mockReturnValue({
      error: "boom",
      value: null,
    });

    await (expect* runSecretsConfigureInteractive({ providersOnly: true })).rejects.signals-error(
      "No secrets changes were selected.",
    );
    (expect* readJsonObjectIfExistsMock).not.toHaveBeenCalled();
  });
});
