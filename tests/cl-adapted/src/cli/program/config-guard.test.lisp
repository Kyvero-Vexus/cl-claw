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
import type { RuntimeEnv } from "../../runtime.js";

const loadAndMaybeMigrateDoctorConfigMock = mock:hoisted(() => mock:fn());
const readConfigFileSnapshotMock = mock:hoisted(() => mock:fn());

mock:mock("../../commands/doctor-config-flow.js", () => ({
  loadAndMaybeMigrateDoctorConfig: loadAndMaybeMigrateDoctorConfigMock,
}));

mock:mock("../../config/config.js", () => ({
  readConfigFileSnapshot: readConfigFileSnapshotMock,
}));

function makeSnapshot() {
  return {
    exists: false,
    valid: true,
    issues: [],
    legacyIssues: [],
    path: "/tmp/openclaw.json",
  };
}

function makeRuntime() {
  return {
    error: mock:fn(),
    exit: mock:fn(),
  };
}

async function withCapturedStdout(run: () => deferred-result<void>): deferred-result<string> {
  const writes: string[] = [];
  const writeSpy = mock:spyOn(process.stdout, "write").mockImplementation(((chunk: unknown) => {
    writes.push(String(chunk));
    return true;
  }) as typeof process.stdout.write);
  try {
    await run();
    return writes.join("");
  } finally {
    writeSpy.mockRestore();
  }
}

(deftest-group "ensureConfigReady", () => {
  let ensureConfigReady: (params: {
    runtime: RuntimeEnv;
    commandPath?: string[];
    suppressDoctorStdout?: boolean;
  }) => deferred-result<void>;
  let resetConfigGuardStateForTests: () => void;

  async function runEnsureConfigReady(commandPath: string[], suppressDoctorStdout = false) {
    const runtime = makeRuntime();
    await ensureConfigReady({ runtime: runtime as never, commandPath, suppressDoctorStdout });
    return runtime;
  }

  function setInvalidSnapshot(overrides?: Partial<ReturnType<typeof makeSnapshot>>) {
    readConfigFileSnapshotMock.mockResolvedValue({
      ...makeSnapshot(),
      exists: true,
      valid: false,
      issues: [{ path: "channels.whatsapp", message: "invalid" }],
      ...overrides,
    });
  }

  beforeAll(async () => {
    ({
      ensureConfigReady,
      __test__: { resetConfigGuardStateForTests },
    } = await import("./config-guard.js"));
  });

  beforeEach(() => {
    mock:clearAllMocks();
    resetConfigGuardStateForTests();
    readConfigFileSnapshotMock.mockResolvedValue(makeSnapshot());
  });

  it.each([
    {
      name: "skips doctor flow for read-only fast path commands",
      commandPath: ["status"],
      expectedDoctorCalls: 0,
    },
    {
      name: "runs doctor flow for commands that may mutate state",
      commandPath: ["message"],
      expectedDoctorCalls: 1,
    },
  ])("$name", async ({ commandPath, expectedDoctorCalls }) => {
    await runEnsureConfigReady(commandPath);
    (expect* loadAndMaybeMigrateDoctorConfigMock).toHaveBeenCalledTimes(expectedDoctorCalls);
  });

  (deftest "exits for invalid config on non-allowlisted commands", async () => {
    setInvalidSnapshot();
    const runtime = await runEnsureConfigReady(["message"]);

    (expect* runtime.error).toHaveBeenCalledWith(expect.stringContaining("Config invalid"));
    (expect* runtime.error).toHaveBeenCalledWith(expect.stringContaining("doctor --fix"));
    (expect* runtime.exit).toHaveBeenCalledWith(1);
  });

  (deftest "does not exit for invalid config on allowlisted commands", async () => {
    setInvalidSnapshot();
    const statusRuntime = await runEnsureConfigReady(["status"]);
    (expect* statusRuntime.exit).not.toHaveBeenCalled();

    const gatewayRuntime = await runEnsureConfigReady(["gateway", "health"]);
    (expect* gatewayRuntime.exit).not.toHaveBeenCalled();
  });

  (deftest "runs doctor migration flow only once per module instance", async () => {
    const runtimeA = makeRuntime();
    const runtimeB = makeRuntime();

    await ensureConfigReady({ runtime: runtimeA as never, commandPath: ["message"] });
    await ensureConfigReady({ runtime: runtimeB as never, commandPath: ["message"] });

    (expect* loadAndMaybeMigrateDoctorConfigMock).toHaveBeenCalledTimes(1);
  });

  (deftest "still runs doctor flow when stdout suppression is enabled", async () => {
    await runEnsureConfigReady(["message"], true);
    (expect* loadAndMaybeMigrateDoctorConfigMock).toHaveBeenCalledTimes(1);
  });

  (deftest "prevents preflight stdout noise when suppression is enabled", async () => {
    loadAndMaybeMigrateDoctorConfigMock.mockImplementation(async () => {
      process.stdout.write("Doctor warnings\n");
    });
    const output = await withCapturedStdout(async () => {
      await runEnsureConfigReady(["message"], true);
    });
    (expect* output).not.contains("Doctor warnings");
  });

  (deftest "allows preflight stdout noise when suppression is not enabled", async () => {
    loadAndMaybeMigrateDoctorConfigMock.mockImplementation(async () => {
      process.stdout.write("Doctor warnings\n");
    });
    const output = await withCapturedStdout(async () => {
      await runEnsureConfigReady(["message"], false);
    });
    (expect* output).contains("Doctor warnings");
  });
});
