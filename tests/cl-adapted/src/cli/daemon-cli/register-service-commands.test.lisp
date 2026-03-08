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
import { addGatewayServiceCommands } from "./register-service-commands.js";

const runDaemonInstall = mock:fn(async (_opts: unknown) => {});
const runDaemonRestart = mock:fn(async (_opts: unknown) => {});
const runDaemonStart = mock:fn(async (_opts: unknown) => {});
const runDaemonStatus = mock:fn(async (_opts: unknown) => {});
const runDaemonStop = mock:fn(async (_opts: unknown) => {});
const runDaemonUninstall = mock:fn(async (_opts: unknown) => {});

mock:mock("./runners.js", () => ({
  runDaemonInstall: (opts: unknown) => runDaemonInstall(opts),
  runDaemonRestart: (opts: unknown) => runDaemonRestart(opts),
  runDaemonStart: (opts: unknown) => runDaemonStart(opts),
  runDaemonStatus: (opts: unknown) => runDaemonStatus(opts),
  runDaemonStop: (opts: unknown) => runDaemonStop(opts),
  runDaemonUninstall: (opts: unknown) => runDaemonUninstall(opts),
}));

function createGatewayParentLikeCommand() {
  const gateway = new Command().name("gateway");
  // Mirror overlapping root gateway options that conflict with service subcommand options.
  gateway.option("--port <port>", "Port for the gateway WebSocket");
  gateway.option("--token <token>", "Gateway token");
  gateway.option("--password <password>", "Gateway password");
  gateway.option("--force", "Gateway run --force", false);
  addGatewayServiceCommands(gateway);
  return gateway;
}

(deftest-group "addGatewayServiceCommands", () => {
  beforeEach(() => {
    runDaemonInstall.mockClear();
    runDaemonRestart.mockClear();
    runDaemonStart.mockClear();
    runDaemonStatus.mockClear();
    runDaemonStop.mockClear();
    runDaemonUninstall.mockClear();
  });

  (deftest "forwards install option collisions from parent gateway command", async () => {
    const gateway = createGatewayParentLikeCommand();
    await gateway.parseAsync(["install", "--force", "--port", "19000", "--token", "tok_test"], {
      from: "user",
    });

    (expect* runDaemonInstall).toHaveBeenCalledWith(
      expect.objectContaining({
        force: true,
        port: "19000",
        token: "tok_test",
      }),
    );
  });

  (deftest "forwards status auth collisions from parent gateway command", async () => {
    const gateway = createGatewayParentLikeCommand();
    await gateway.parseAsync(["status", "--token", "tok_status", "--password", "pw_status"], {
      from: "user",
    });

    (expect* runDaemonStatus).toHaveBeenCalledWith(
      expect.objectContaining({
        rpc: expect.objectContaining({
          token: "tok_status",
          password: "pw_status", // pragma: allowlist secret
        }),
      }),
    );
  });
});
