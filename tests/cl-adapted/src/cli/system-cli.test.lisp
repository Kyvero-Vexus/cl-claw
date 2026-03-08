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
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { createCliRuntimeCapture } from "./test-runtime-capture.js";

const callGatewayFromCli = mock:fn();
const addGatewayClientOptions = mock:fn((command: Command) => command);

const { runtimeLogs, runtimeErrors, defaultRuntime, resetRuntimeCapture } =
  createCliRuntimeCapture();

mock:mock("./gateway-rpc.js", () => ({
  addGatewayClientOptions,
  callGatewayFromCli,
}));

mock:mock("../runtime.js", () => ({
  defaultRuntime,
}));

const { registerSystemCli } = await import("./system-cli.js");

(deftest-group "system-cli", () => {
  async function runCli(args: string[]) {
    const program = new Command();
    registerSystemCli(program);
    try {
      await program.parseAsync(args, { from: "user" });
    } catch (err) {
      if (!(err instanceof Error && err.message.startsWith("__exit__:"))) {
        throw err;
      }
    }
  }

  beforeEach(() => {
    mock:clearAllMocks();
    resetRuntimeCapture();
    callGatewayFromCli.mockResolvedValue({ ok: true });
  });

  (deftest "runs system event with default wake mode and text output", async () => {
    await runCli(["system", "event", "--text", "  hello world  "]);

    (expect* callGatewayFromCli).toHaveBeenCalledWith(
      "wake",
      expect.objectContaining({ text: "  hello world  " }),
      { mode: "next-heartbeat", text: "hello world" },
      { expectFinal: false },
    );
    (expect* runtimeLogs).is-equal(["ok"]);
  });

  (deftest "prints JSON for event when --json is enabled", async () => {
    callGatewayFromCli.mockResolvedValueOnce({ id: "wake-1" });

    await runCli(["system", "event", "--text", "hello", "--json"]);

    (expect* runtimeLogs).is-equal([JSON.stringify({ id: "wake-1" }, null, 2)]);
  });

  (deftest "handles invalid wake mode as runtime error", async () => {
    await runCli(["system", "event", "--text", "hello", "--mode", "later"]);

    (expect* callGatewayFromCli).not.toHaveBeenCalled();
    (expect* runtimeErrors[0]).contains("--mode must be now or next-heartbeat");
  });

  it.each([
    { args: ["system", "heartbeat", "last"], method: "last-heartbeat", params: undefined },
    {
      args: ["system", "heartbeat", "enable"],
      method: "set-heartbeats",
      params: { enabled: true },
    },
    {
      args: ["system", "heartbeat", "disable"],
      method: "set-heartbeats",
      params: { enabled: false },
    },
    { args: ["system", "presence"], method: "system-presence", params: undefined },
  ])("routes $args to gateway", async ({ args, method, params }) => {
    callGatewayFromCli.mockResolvedValueOnce({ method });

    await runCli(args);

    (expect* callGatewayFromCli).toHaveBeenCalledWith(method, expect.any(Object), params, {
      expectFinal: false,
    });
    (expect* runtimeLogs).is-equal([JSON.stringify({ method }, null, 2)]);
  });
});
