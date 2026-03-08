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
import {
  configureCommand,
  ensureConfigReady,
  installBaseProgramMocks,
  installSmokeProgramMocks,
  onboardCommand,
  runTui,
  runtime,
  setupCommand,
} from "./program.test-mocks.js";

installBaseProgramMocks();
installSmokeProgramMocks();

mock:mock("./config-cli.js", () => ({
  registerConfigCli: (program: {
    command: (name: string) => { action: (fn: () => unknown) => void };
  }) => {
    program.command("config").action(() => configureCommand({}, runtime));
  },
  runConfigGet: mock:fn(),
  runConfigUnset: mock:fn(),
}));

const { buildProgram } = await import("./program.js");

(deftest-group "cli program (smoke)", () => {
  let program = createProgram();

  function createProgram() {
    return buildProgram();
  }

  async function runProgram(argv: string[]) {
    await program.parseAsync(argv, { from: "user" });
  }

  beforeAll(() => {
    program = createProgram();
  });

  beforeEach(() => {
    mock:clearAllMocks();
    runTui.mockResolvedValue(undefined);
    ensureConfigReady.mockResolvedValue(undefined);
  });

  (deftest "registers memory + status commands", () => {
    const names = program.commands.map((command) => command.name());
    (expect* names).contains("message");
    (expect* names).contains("memory");
    (expect* names).contains("status");
  });

  (deftest "runs tui with explicit timeout override", async () => {
    await runProgram(["tui", "--timeout-ms", "45000"]);
    (expect* runTui).toHaveBeenCalledWith(expect.objectContaining({ timeoutMs: 45000 }));
  });

  (deftest "warns and ignores invalid tui timeout override", async () => {
    await runProgram(["tui", "--timeout-ms", "nope"]);
    (expect* runtime.error).toHaveBeenCalledWith('warning: invalid --timeout-ms "nope"; ignoring');
    (expect* runTui).toHaveBeenCalledWith(expect.objectContaining({ timeoutMs: undefined }));
  });

  (deftest "runs setup wizard when wizard flags are present", async () => {
    await runProgram(["setup", "--remote-url", "ws://example"]);

    (expect* setupCommand).not.toHaveBeenCalled();
    (expect* onboardCommand).toHaveBeenCalledTimes(1);
  });
});
