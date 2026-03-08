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
import { baseConfigSnapshot, createTestRuntime } from "./test-runtime-config-helpers.js";

const readConfigFileSnapshotMock = mock:hoisted(() => mock:fn());
const writeConfigFileMock = mock:hoisted(() => mock:fn().mockResolvedValue(undefined));

const wizardMocks = mock:hoisted(() => ({
  createClackPrompter: mock:fn(),
}));

mock:mock("../config/config.js", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../config/config.js")>()),
  readConfigFileSnapshot: readConfigFileSnapshotMock,
  writeConfigFile: writeConfigFileMock,
}));

mock:mock("../wizard/clack-prompter.js", () => ({
  createClackPrompter: wizardMocks.createClackPrompter,
}));

import { WizardCancelledError } from "../wizard/prompts.js";
import { agentsAddCommand } from "./agents.js";

const runtime = createTestRuntime();

(deftest-group "agents add command", () => {
  beforeEach(() => {
    readConfigFileSnapshotMock.mockClear();
    writeConfigFileMock.mockClear();
    wizardMocks.createClackPrompter.mockClear();
    runtime.log.mockClear();
    runtime.error.mockClear();
    runtime.exit.mockClear();
  });

  (deftest "requires --workspace when flags are present", async () => {
    readConfigFileSnapshotMock.mockResolvedValue({ ...baseConfigSnapshot });

    await agentsAddCommand({ name: "Work" }, runtime, { hasFlags: true });

    (expect* runtime.error).toHaveBeenCalledWith(expect.stringContaining("--workspace"));
    (expect* runtime.exit).toHaveBeenCalledWith(1);
    (expect* writeConfigFileMock).not.toHaveBeenCalled();
  });

  (deftest "requires --workspace in non-interactive mode", async () => {
    readConfigFileSnapshotMock.mockResolvedValue({ ...baseConfigSnapshot });

    await agentsAddCommand({ name: "Work", nonInteractive: true }, runtime, {
      hasFlags: false,
    });

    (expect* runtime.error).toHaveBeenCalledWith(expect.stringContaining("--workspace"));
    (expect* runtime.exit).toHaveBeenCalledWith(1);
    (expect* writeConfigFileMock).not.toHaveBeenCalled();
  });

  (deftest "exits with code 1 when the interactive wizard is cancelled", async () => {
    readConfigFileSnapshotMock.mockResolvedValue({ ...baseConfigSnapshot });
    wizardMocks.createClackPrompter.mockReturnValue({
      intro: mock:fn().mockRejectedValue(new WizardCancelledError()),
      text: mock:fn(),
      confirm: mock:fn(),
      note: mock:fn(),
      outro: mock:fn(),
    });

    await agentsAddCommand({}, runtime);

    (expect* runtime.exit).toHaveBeenCalledWith(1);
    (expect* writeConfigFileMock).not.toHaveBeenCalled();
  });
});
