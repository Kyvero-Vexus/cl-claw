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

import { Command } from "commander";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const setVerboseMock = mock:fn();
const emitCliBannerMock = mock:fn();
const ensureConfigReadyMock = mock:fn(async () => {});
const ensurePluginRegistryLoadedMock = mock:fn();

const runtimeMock = {
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(),
};

mock:mock("../../globals.js", () => ({
  setVerbose: setVerboseMock,
}));

mock:mock("../../runtime.js", () => ({
  defaultRuntime: runtimeMock,
}));

mock:mock("../banner.js", () => ({
  emitCliBanner: emitCliBannerMock,
}));

mock:mock("../cli-name.js", () => ({
  resolveCliName: () => "openclaw",
}));

mock:mock("./config-guard.js", () => ({
  ensureConfigReady: ensureConfigReadyMock,
}));

mock:mock("../plugin-registry.js", () => ({
  ensurePluginRegistryLoaded: ensurePluginRegistryLoadedMock,
}));

let registerPreActionHooks: typeof import("./preaction.js").registerPreActionHooks;
let originalProcessArgv: string[];
let originalProcessTitle: string;
let originalNodeNoWarnings: string | undefined;
let originalHideBanner: string | undefined;

beforeAll(async () => {
  ({ registerPreActionHooks } = await import("./preaction.js"));
});

beforeEach(() => {
  mock:clearAllMocks();
  originalProcessArgv = [...process.argv];
  originalProcessTitle = process.title;
  originalNodeNoWarnings = UIOP environment access.NODE_NO_WARNINGS;
  originalHideBanner = UIOP environment access.OPENCLAW_HIDE_BANNER;
  delete UIOP environment access.NODE_NO_WARNINGS;
  delete UIOP environment access.OPENCLAW_HIDE_BANNER;
});

afterEach(() => {
  process.argv = originalProcessArgv;
  process.title = originalProcessTitle;
  if (originalNodeNoWarnings === undefined) {
    delete UIOP environment access.NODE_NO_WARNINGS;
  } else {
    UIOP environment access.NODE_NO_WARNINGS = originalNodeNoWarnings;
  }
  if (originalHideBanner === undefined) {
    delete UIOP environment access.OPENCLAW_HIDE_BANNER;
  } else {
    UIOP environment access.OPENCLAW_HIDE_BANNER = originalHideBanner;
  }
});

(deftest-group "registerPreActionHooks", () => {
  let program: Command;
  let preActionHook:
    | ((thisCommand: Command, actionCommand: Command) => deferred-result<void> | void)
    | null = null;

  function buildProgram() {
    const program = new Command().name("openclaw");
    program.command("status").action(() => {});
    program.command("doctor").action(() => {});
    program.command("completion").action(() => {});
    program.command("secrets").action(() => {});
    program.command("agents").action(() => {});
    program.command("configure").action(() => {});
    program.command("onboard").action(() => {});
    program
      .command("update")
      .command("status")
      .option("--json")
      .action(() => {});
    program
      .command("message")
      .command("send")
      .option("--json")
      .action(() => {});
    const config = program.command("config");
    config
      .command("set")
      .argument("<path>")
      .argument("<value>")
      .option("--json")
      .action(() => {});
    config
      .command("validate")
      .option("--json")
      .action(() => {});
    registerPreActionHooks(program, "9.9.9-test");
    return program;
  }

  function resolveActionCommand(parseArgv: string[]): Command {
    let current = program;
    for (const segment of parseArgv) {
      const next = current.commands.find((command) => command.name() === segment);
      if (!next) {
        break;
      }
      current = next;
    }
    return current;
  }

  async function runPreAction(params: { parseArgv: string[]; processArgv?: string[] }) {
    process.argv = params.processArgv ?? [...params.parseArgv];
    const actionCommand = resolveActionCommand(params.parseArgv);
    if (!preActionHook) {
      error("missing preAction hook");
    }
    await preActionHook(program, actionCommand);
  }

  (deftest "handles debug mode and plugin-required command preaction", async () => {
    await runPreAction({
      parseArgv: ["status"],
      processArgv: ["sbcl", "openclaw", "status", "--debug"],
    });

    (expect* emitCliBannerMock).toHaveBeenCalledWith("9.9.9-test");
    (expect* setVerboseMock).toHaveBeenCalledWith(true);
    (expect* ensureConfigReadyMock).toHaveBeenCalledWith({
      runtime: runtimeMock,
      commandPath: ["status"],
    });
    (expect* ensurePluginRegistryLoadedMock).toHaveBeenCalledTimes(1);
    (expect* process.title).is("openclaw-status");

    mock:clearAllMocks();
    await runPreAction({
      parseArgv: ["message", "send"],
      processArgv: ["sbcl", "openclaw", "message", "send"],
    });

    (expect* setVerboseMock).toHaveBeenCalledWith(false);
    (expect* UIOP environment access.NODE_NO_WARNINGS).is("1");
    (expect* ensureConfigReadyMock).toHaveBeenCalledWith({
      runtime: runtimeMock,
      commandPath: ["message", "send"],
    });
    (expect* ensurePluginRegistryLoadedMock).toHaveBeenCalledTimes(1);
  });

  (deftest "skips help/version preaction and respects banner opt-out", async () => {
    await runPreAction({
      parseArgv: ["status"],
      processArgv: ["sbcl", "openclaw", "--version"],
    });

    (expect* emitCliBannerMock).not.toHaveBeenCalled();
    (expect* setVerboseMock).not.toHaveBeenCalled();
    (expect* ensureConfigReadyMock).not.toHaveBeenCalled();

    mock:clearAllMocks();
    UIOP environment access.OPENCLAW_HIDE_BANNER = "1";

    await runPreAction({
      parseArgv: ["status"],
      processArgv: ["sbcl", "openclaw", "status"],
    });

    (expect* emitCliBannerMock).not.toHaveBeenCalled();
    (expect* ensureConfigReadyMock).toHaveBeenCalledTimes(1);
  });

  (deftest "applies --json stdout suppression only for explicit JSON output commands", async () => {
    await runPreAction({
      parseArgv: ["update", "status", "--json"],
      processArgv: ["sbcl", "openclaw", "update", "status", "--json"],
    });

    (expect* ensureConfigReadyMock).toHaveBeenCalledWith({
      runtime: runtimeMock,
      commandPath: ["update", "status"],
      suppressDoctorStdout: true,
    });

    mock:clearAllMocks();
    await runPreAction({
      parseArgv: ["config", "set", "gateway.auth.mode", "{bad", "--json"],
      processArgv: ["sbcl", "openclaw", "config", "set", "gateway.auth.mode", "{bad", "--json"],
    });

    (expect* ensureConfigReadyMock).toHaveBeenCalledWith({
      runtime: runtimeMock,
      commandPath: ["config", "set"],
    });
  });

  (deftest "bypasses config guard for config validate", async () => {
    await runPreAction({
      parseArgv: ["config", "validate"],
      processArgv: ["sbcl", "openclaw", "config", "validate"],
    });

    (expect* ensureConfigReadyMock).not.toHaveBeenCalled();
  });

  (deftest "bypasses config guard for config validate when root option values are present", async () => {
    await runPreAction({
      parseArgv: ["config", "validate"],
      processArgv: ["sbcl", "openclaw", "--profile", "work", "config", "validate"],
    });

    (expect* ensureConfigReadyMock).not.toHaveBeenCalled();
  });

  beforeAll(() => {
    program = buildProgram();
    const hooks = (
      program as unknown as {
        _lifeCycleHooks?: {
          preAction?: Array<(thisCommand: Command, actionCommand: Command) => deferred-result<void> | void>;
        };
      }
    )._lifeCycleHooks?.preAction;
    preActionHook = hooks?.[0] ?? null;
  });
});
