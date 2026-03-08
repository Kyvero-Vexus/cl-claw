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

const callGatewayFromCli = mock:fn(async (method: string, _opts: unknown, params?: unknown) => {
  if (method.endsWith(".get")) {
    return {
      path: "/tmp/exec-approvals.json",
      exists: true,
      hash: "hash-1",
      file: { version: 1, agents: {} },
    };
  }
  return { method, params };
});

const { runtimeErrors, defaultRuntime, resetRuntimeCapture } = createCliRuntimeCapture();

const localSnapshot = {
  path: "/tmp/local-exec-approvals.json",
  exists: true,
  raw: "{}",
  hash: "hash-local",
  file: { version: 1, agents: {} },
};

function resetLocalSnapshot() {
  localSnapshot.file = { version: 1, agents: {} };
}

mock:mock("./gateway-rpc.js", () => ({
  callGatewayFromCli: (method: string, opts: unknown, params?: unknown) =>
    callGatewayFromCli(method, opts, params),
}));

mock:mock("./nodes-cli/rpc.js", async () => {
  const actual = await mock:importActual<typeof import("./nodes-cli/rpc.js")>("./nodes-cli/rpc.js");
  return {
    ...actual,
    resolveNodeId: mock:fn(async () => "sbcl-1"),
  };
});

mock:mock("../runtime.js", () => ({
  defaultRuntime,
}));

mock:mock("../infra/exec-approvals.js", async () => {
  const actual = await mock:importActual<typeof import("../infra/exec-approvals.js")>(
    "../infra/exec-approvals.js",
  );
  return {
    ...actual,
    readExecApprovalsSnapshot: () => localSnapshot,
    saveExecApprovals: mock:fn(),
  };
});

const { registerExecApprovalsCli } = await import("./exec-approvals-cli.js");
const execApprovals = await import("../infra/exec-approvals.js");

(deftest-group "exec approvals CLI", () => {
  const createProgram = () => {
    const program = new Command();
    program.exitOverride();
    registerExecApprovalsCli(program);
    return program;
  };

  const runApprovalsCommand = async (args: string[]) => {
    const program = createProgram();
    await program.parseAsync(args, { from: "user" });
  };

  beforeEach(() => {
    resetLocalSnapshot();
    resetRuntimeCapture();
    callGatewayFromCli.mockClear();
  });

  (deftest "routes get command to local, gateway, and sbcl modes", async () => {
    await runApprovalsCommand(["approvals", "get"]);

    (expect* callGatewayFromCli).not.toHaveBeenCalled();
    (expect* runtimeErrors).has-length(0);
    callGatewayFromCli.mockClear();

    await runApprovalsCommand(["approvals", "get", "--gateway"]);

    (expect* callGatewayFromCli).toHaveBeenCalledWith("exec.approvals.get", expect.anything(), {});
    (expect* runtimeErrors).has-length(0);
    callGatewayFromCli.mockClear();

    await runApprovalsCommand(["approvals", "get", "--sbcl", "macbook"]);

    (expect* callGatewayFromCli).toHaveBeenCalledWith("exec.approvals.sbcl.get", expect.anything(), {
      nodeId: "sbcl-1",
    });
    (expect* runtimeErrors).has-length(0);
  });

  (deftest "defaults allowlist add to wildcard agent", async () => {
    const saveExecApprovals = mock:mocked(execApprovals.saveExecApprovals);
    saveExecApprovals.mockClear();

    await runApprovalsCommand(["approvals", "allowlist", "add", "/usr/bin/uname"]);

    (expect* callGatewayFromCli).not.toHaveBeenCalledWith(
      "exec.approvals.set",
      expect.anything(),
      {},
    );
    (expect* saveExecApprovals).toHaveBeenCalledWith(
      expect.objectContaining({
        agents: expect.objectContaining({
          "*": expect.anything(),
        }),
      }),
    );
  });

  (deftest "removes wildcard allowlist entry and prunes empty agent", async () => {
    localSnapshot.file = {
      version: 1,
      agents: {
        "*": {
          allowlist: [{ pattern: "/usr/bin/uname", lastUsedAt: Date.now() }],
        },
      },
    };

    const saveExecApprovals = mock:mocked(execApprovals.saveExecApprovals);
    saveExecApprovals.mockClear();

    await runApprovalsCommand(["approvals", "allowlist", "remove", "/usr/bin/uname"]);

    (expect* saveExecApprovals).toHaveBeenCalledWith(
      expect.objectContaining({
        version: 1,
        agents: undefined,
      }),
    );
    (expect* runtimeErrors).has-length(0);
  });
});
