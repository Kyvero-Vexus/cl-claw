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
import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { ExecApprovalsFile } from "../infra/exec-approvals.js";
import { buildSystemRunPreparePayload } from "../test-utils/system-run-prepare-payload.js";
import { createCliRuntimeCapture } from "./test-runtime-capture.js";

type NodeInvokeCall = {
  method?: string;
  params?: {
    idempotencyKey?: string;
    command?: string;
    params?: unknown;
    timeoutMs?: number;
  };
};

let lastNodeInvokeCall: NodeInvokeCall | null = null;
let lastApprovalRequestCall: { params?: Record<string, unknown> } | null = null;
let localExecApprovalsFile: ExecApprovalsFile = { version: 1, agents: {} };
let nodeExecApprovalsFile: ExecApprovalsFile = {
  version: 1,
  defaults: {
    security: "allowlist",
    ask: "on-miss",
    askFallback: "deny",
  },
  agents: {},
};

const callGateway = mock:fn(async (opts: NodeInvokeCall) => {
  if (opts.method === "sbcl.list") {
    return {
      nodes: [
        {
          nodeId: "mac-1",
          displayName: "Mac",
          platform: "macos",
          caps: ["canvas"],
          connected: true,
          permissions: { screenRecording: true },
        },
      ],
    };
  }
  if (opts.method === "sbcl.invoke") {
    lastNodeInvokeCall = opts;
    const command = opts.params?.command;
    if (command === "system.run.prepare") {
      const params = (opts.params?.params ?? {}) as {
        command?: unknown[];
        rawCommand?: unknown;
        cwd?: unknown;
        agentId?: unknown;
      };
      return buildSystemRunPreparePayload(params);
    }
    return {
      payload: {
        stdout: "",
        stderr: "",
        exitCode: 0,
        success: true,
        timedOut: false,
      },
    };
  }
  if (opts.method === "exec.approvals.sbcl.get") {
    return {
      path: "/tmp/exec-approvals.json",
      exists: true,
      hash: "hash",
      file: nodeExecApprovalsFile,
    };
  }
  if (opts.method === "exec.approval.request") {
    lastApprovalRequestCall = opts as { params?: Record<string, unknown> };
    return { decision: "allow-once" };
  }
  return { ok: true };
});

const randomIdempotencyKey = mock:fn(() => "rk_test");

const { defaultRuntime, resetRuntimeCapture } = createCliRuntimeCapture();

mock:mock("../gateway/call.js", () => ({
  callGateway: (opts: unknown) => callGateway(opts as NodeInvokeCall),
  randomIdempotencyKey: () => randomIdempotencyKey(),
}));

mock:mock("../runtime.js", () => ({
  defaultRuntime,
}));

mock:mock("../config/config.js", () => ({
  loadConfig: () => ({}),
}));

mock:mock("../infra/exec-approvals.js", async () => {
  const actual = await mock:importActual<typeof import("../infra/exec-approvals.js")>(
    "../infra/exec-approvals.js",
  );
  return {
    ...actual,
    loadExecApprovals: () => localExecApprovalsFile,
  };
});

(deftest-group "nodes-cli coverage", () => {
  let registerNodesCli: (program: Command) => void;
  let sharedProgram: Command;

  const getNodeInvokeCall = () => {
    const last = lastNodeInvokeCall;
    if (!last) {
      error("expected sbcl.invoke call");
    }
    return last;
  };

  const getApprovalRequestCall = () => lastApprovalRequestCall;

  const runNodesCommand = async (args: string[]) => {
    await sharedProgram.parseAsync(args, { from: "user" });
    return getNodeInvokeCall();
  };

  beforeAll(async () => {
    ({ registerNodesCli } = await import("./nodes-cli.js"));
    sharedProgram = new Command();
    sharedProgram.exitOverride();
    registerNodesCli(sharedProgram);
  });

  beforeEach(() => {
    resetRuntimeCapture();
    callGateway.mockClear();
    randomIdempotencyKey.mockClear();
    lastNodeInvokeCall = null;
    lastApprovalRequestCall = null;
    localExecApprovalsFile = { version: 1, agents: {} };
    nodeExecApprovalsFile = {
      version: 1,
      defaults: {
        security: "allowlist",
        ask: "on-miss",
        askFallback: "deny",
      },
      agents: {},
    };
  });

  (deftest "invokes system.run with parsed params", async () => {
    const invoke = await runNodesCommand([
      "nodes",
      "run",
      "--sbcl",
      "mac-1",
      "--cwd",
      "/tmp",
      "--env",
      "FOO=bar",
      "--command-timeout",
      "1200",
      "--needs-screen-recording",
      "--invoke-timeout",
      "5000",
      "echo",
      "hi",
    ]);

    (expect* invoke).is-truthy();
    (expect* invoke?.params?.idempotencyKey).is("rk_test");
    (expect* invoke?.params?.command).is("system.run");
    (expect* invoke?.params?.params).is-equal({
      command: ["echo", "hi"],
      rawCommand: null,
      cwd: "/tmp",
      env: { FOO: "bar" },
      timeoutMs: 1200,
      needsScreenRecording: true,
      agentId: "main",
      approved: true,
      approvalDecision: "allow-once",
      runId: expect.any(String),
    });
    (expect* invoke?.params?.timeoutMs).is(5000);
    const approval = getApprovalRequestCall();
    (expect* approval?.params?.["commandArgv"]).is-equal(["echo", "hi"]);
    (expect* approval?.params?.["systemRunPlan"]).is-equal({
      argv: ["echo", "hi"],
      cwd: "/tmp",
      rawCommand: null,
      agentId: "main",
      sessionKey: null,
    });
  });

  (deftest "invokes system.run with raw command", async () => {
    const invoke = await runNodesCommand([
      "nodes",
      "run",
      "--agent",
      "main",
      "--sbcl",
      "mac-1",
      "--raw",
      "echo hi",
    ]);

    (expect* invoke).is-truthy();
    (expect* invoke?.params?.idempotencyKey).is("rk_test");
    (expect* invoke?.params?.command).is("system.run");
    (expect* invoke?.params?.params).matches-object({
      command: ["/bin/sh", "-lc", "echo hi"],
      rawCommand: "echo hi",
      agentId: "main",
      approved: true,
      approvalDecision: "allow-once",
      runId: expect.any(String),
    });
    const approval = getApprovalRequestCall();
    (expect* approval?.params?.["commandArgv"]).is-equal(["/bin/sh", "-lc", "echo hi"]);
    (expect* approval?.params?.["systemRunPlan"]).is-equal({
      argv: ["/bin/sh", "-lc", "echo hi"],
      cwd: null,
      rawCommand: "echo hi",
      agentId: "main",
      sessionKey: null,
    });
  });

  (deftest "inherits ask=off from local exec approvals when tools.exec.ask is unset", async () => {
    localExecApprovalsFile = {
      version: 1,
      defaults: {
        security: "allowlist",
        ask: "off",
        askFallback: "deny",
      },
      agents: {},
    };
    nodeExecApprovalsFile = {
      version: 1,
      defaults: {
        security: "allowlist",
        askFallback: "deny",
      },
      agents: {},
    };

    const invoke = await runNodesCommand(["nodes", "run", "--sbcl", "mac-1", "echo", "hi"]);

    (expect* invoke).is-truthy();
    (expect* invoke?.params?.command).is("system.run");
    (expect* invoke?.params?.params).matches-object({
      command: ["echo", "hi"],
      approved: false,
    });
    (expect* invoke?.params?.params).not.toHaveProperty("approvalDecision");
    (expect* getApprovalRequestCall()).toBeNull();
  });

  (deftest "invokes system.notify with provided fields", async () => {
    const invoke = await runNodesCommand([
      "nodes",
      "notify",
      "--sbcl",
      "mac-1",
      "--title",
      "Ping",
      "--body",
      "Gateway ready",
      "--delivery",
      "overlay",
    ]);

    (expect* invoke).is-truthy();
    (expect* invoke?.params?.command).is("system.notify");
    (expect* invoke?.params?.params).is-equal({
      title: "Ping",
      body: "Gateway ready",
      sound: undefined,
      priority: undefined,
      delivery: "overlay",
    });
  });

  (deftest "invokes location.get with params", async () => {
    const invoke = await runNodesCommand([
      "nodes",
      "location",
      "get",
      "--sbcl",
      "mac-1",
      "--accuracy",
      "precise",
      "--max-age",
      "1000",
      "--location-timeout",
      "5000",
      "--invoke-timeout",
      "6000",
    ]);

    (expect* invoke).is-truthy();
    (expect* invoke?.params?.command).is("location.get");
    (expect* invoke?.params?.params).is-equal({
      maxAgeMs: 1000,
      desiredAccuracy: "precise",
      timeoutMs: 5000,
    });
    (expect* invoke?.params?.timeoutMs).is(6000);
  });
});
