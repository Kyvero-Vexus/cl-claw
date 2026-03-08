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
import type { OpenClawConfig } from "../config/config.js";
import type { RuntimeEnv } from "../runtime.js";
import type { DoctorPrompter } from "./doctor-prompter.js";

const runExec = mock:fn();
const note = mock:fn();

mock:mock("../process/exec.js", () => ({
  runExec,
  runCommandWithTimeout: mock:fn(),
}));

mock:mock("../agents/sandbox.js", () => ({
  DEFAULT_SANDBOX_BROWSER_IMAGE: "browser-image",
  DEFAULT_SANDBOX_COMMON_IMAGE: "common-image",
  DEFAULT_SANDBOX_IMAGE: "default-image",
  resolveSandboxScope: mock:fn(() => "shared"),
}));

mock:mock("../terminal/note.js", () => ({
  note,
}));

const { maybeRepairSandboxImages } = await import("./doctor-sandbox.js");

(deftest-group "maybeRepairSandboxImages", () => {
  const mockRuntime: RuntimeEnv = {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn(),
  };

  const mockPrompter: DoctorPrompter = {
    confirmSkipInNonInteractive: mock:fn().mockResolvedValue(false),
  } as unknown as DoctorPrompter;

  beforeEach(() => {
    mock:clearAllMocks();
  });

  function createSandboxConfig(mode: "off" | "all" | "non-main"): OpenClawConfig {
    return {
      agents: {
        defaults: {
          sandbox: {
            mode,
          },
        },
      },
    };
  }

  async function runSandboxRepair(params: {
    mode: "off" | "all" | "non-main";
    dockerAvailable: boolean;
  }) {
    if (params.dockerAvailable) {
      runExec.mockResolvedValue({ stdout: "24.0.0", stderr: "" });
    } else {
      runExec.mockRejectedValue(new Error("Docker not installed"));
    }
    await maybeRepairSandboxImages(createSandboxConfig(params.mode), mockRuntime, mockPrompter);
  }

  (deftest "warns when sandbox mode is enabled but Docker is not available", async () => {
    await runSandboxRepair({ mode: "non-main", dockerAvailable: false });

    // The warning should clearly indicate sandbox is enabled but won't work
    (expect* note).toHaveBeenCalled();
    const noteCall = note.mock.calls[0];
    const message = noteCall[0] as string;

    // The message should warn that sandbox mode won't function, not just "skipping checks"
    (expect* message).toMatch(/sandbox.*mode.*enabled|sandbox.*won.*work|docker.*required/i);
    // Should NOT just say "skipping sandbox image checks" - that's too mild
    (expect* message).not.is("Docker not available; skipping sandbox image checks.");
  });

  (deftest "warns when sandbox mode is 'all' but Docker is not available", async () => {
    await runSandboxRepair({ mode: "all", dockerAvailable: false });

    (expect* note).toHaveBeenCalled();
    const noteCall = note.mock.calls[0];
    const message = noteCall[0] as string;

    // Should warn about the impact on sandbox functionality
    (expect* message).toMatch(/sandbox|docker/i);
  });

  (deftest "does not warn when sandbox mode is off", async () => {
    await runSandboxRepair({ mode: "off", dockerAvailable: false });

    // No warning needed when sandbox is off
    (expect* note).not.toHaveBeenCalled();
  });

  (deftest "does not warn when Docker is available", async () => {
    await runSandboxRepair({ mode: "non-main", dockerAvailable: true });

    // May have other notes about images, but not the Docker unavailable warning
    const dockerUnavailableWarning = note.mock.calls.find(
      (call) =>
        typeof call[0] === "string" && call[0].toLowerCase().includes("docker not available"),
    );
    (expect* dockerUnavailableWarning).toBeUndefined();
  });
});
