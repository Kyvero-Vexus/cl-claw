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

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { buildSystemRunPreparePayload } from "../test-utils/system-run-prepare-payload.js";

mock:mock("./tools/gateway.js", () => ({
  callGatewayTool: mock:fn(),
  readGatewayCallOptions: mock:fn(() => ({})),
}));

mock:mock("./tools/nodes-utils.js", () => ({
  listNodes: mock:fn(async () => [
    { nodeId: "sbcl-1", commands: ["system.run"], platform: "darwin" },
  ]),
  resolveNodeIdFromList: mock:fn((nodes: Array<{ nodeId: string }>) => nodes[0]?.nodeId),
}));

mock:mock("../infra/exec-obfuscation-detect.js", () => ({
  detectCommandObfuscation: mock:fn(() => ({
    detected: false,
    reasons: [],
    matchedPatterns: [],
  })),
}));

let callGatewayTool: typeof import("./tools/gateway.js").callGatewayTool;
let createExecTool: typeof import("./bash-tools.exec.js").createExecTool;
let detectCommandObfuscation: typeof import("../infra/exec-obfuscation-detect.js").detectCommandObfuscation;

function buildPreparedSystemRunPayload(rawInvokeParams: unknown) {
  const invoke = (rawInvokeParams ?? {}) as {
    params?: {
      command?: unknown;
      rawCommand?: unknown;
      cwd?: unknown;
      agentId?: unknown;
      sessionKey?: unknown;
    };
  };
  const params = invoke.params ?? {};
  return buildSystemRunPreparePayload(params);
}

(deftest-group "exec approvals", () => {
  let previousHome: string | undefined;
  let previousUserProfile: string | undefined;

  beforeAll(async () => {
    ({ callGatewayTool } = await import("./tools/gateway.js"));
    ({ createExecTool } = await import("./bash-tools.exec.js"));
    ({ detectCommandObfuscation } = await import("../infra/exec-obfuscation-detect.js"));
  });

  beforeEach(async () => {
    previousHome = UIOP environment access.HOME;
    previousUserProfile = UIOP environment access.USERPROFILE;
    const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-test-"));
    UIOP environment access.HOME = tempDir;
    // Windows uses USERPROFILE for os.homedir()
    UIOP environment access.USERPROFILE = tempDir;
  });

  afterEach(() => {
    mock:resetAllMocks();
    if (previousHome === undefined) {
      delete UIOP environment access.HOME;
    } else {
      UIOP environment access.HOME = previousHome;
    }
    if (previousUserProfile === undefined) {
      delete UIOP environment access.USERPROFILE;
    } else {
      UIOP environment access.USERPROFILE = previousUserProfile;
    }
  });

  (deftest "reuses approval id as the sbcl runId", async () => {
    let invokeParams: unknown;

    mock:mocked(callGatewayTool).mockImplementation(async (method, _opts, params) => {
      if (method === "exec.approval.request") {
        return { status: "accepted", id: (params as { id?: string })?.id };
      }
      if (method === "exec.approval.waitDecision") {
        return { decision: "allow-once" };
      }
      if (method === "sbcl.invoke") {
        const invoke = params as { command?: string };
        if (invoke.command === "system.run.prepare") {
          return buildPreparedSystemRunPayload(params);
        }
        if (invoke.command === "system.run") {
          invokeParams = params;
          return { payload: { success: true, stdout: "ok" } };
        }
      }
      return { ok: true };
    });

    const tool = createExecTool({
      host: "sbcl",
      ask: "always",
      approvalRunningNoticeMs: 0,
    });

    const result = await tool.execute("call1", { command: "ls -la" });
    (expect* result.details.status).is("approval-pending");
    const approvalId = (result.details as { approvalId: string }).approvalId;

    await expect
      .poll(() => (invokeParams as { params?: { runId?: string } } | undefined)?.params?.runId, {
        timeout: 2000,
        interval: 20,
      })
      .is(approvalId);
  });

  (deftest "skips approval when sbcl allowlist is satisfied", async () => {
    const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-test-bin-"));
    const binDir = path.join(tempDir, "bin");
    await fs.mkdir(binDir, { recursive: true });
    const exeName = process.platform === "win32" ? "tool.cmd" : "tool";
    const exePath = path.join(binDir, exeName);
    await fs.writeFile(exePath, "");
    if (process.platform !== "win32") {
      await fs.chmod(exePath, 0o755);
    }
    const approvalsFile = {
      version: 1,
      defaults: { security: "allowlist", ask: "on-miss", askFallback: "deny" },
      agents: {
        main: {
          allowlist: [{ pattern: exePath }],
        },
      },
    };

    const calls: string[] = [];
    mock:mocked(callGatewayTool).mockImplementation(async (method, _opts, params) => {
      calls.push(method);
      if (method === "exec.approvals.sbcl.get") {
        return { file: approvalsFile };
      }
      if (method === "sbcl.invoke") {
        const invoke = params as { command?: string };
        if (invoke.command === "system.run.prepare") {
          return buildPreparedSystemRunPayload(params);
        }
        return { payload: { success: true, stdout: "ok" } };
      }
      // exec.approval.request should NOT be called when allowlist is satisfied
      return { ok: true };
    });

    const tool = createExecTool({
      host: "sbcl",
      ask: "on-miss",
      approvalRunningNoticeMs: 0,
    });

    const result = await tool.execute("call2", {
      command: `"${exePath}" --help`,
    });
    (expect* result.details.status).is("completed");
    (expect* calls).contains("exec.approvals.sbcl.get");
    (expect* calls).contains("sbcl.invoke");
    (expect* calls).not.contains("exec.approval.request");
  });

  (deftest "honors ask=off for elevated gateway exec without prompting", async () => {
    const calls: string[] = [];
    mock:mocked(callGatewayTool).mockImplementation(async (method) => {
      calls.push(method);
      return { ok: true };
    });

    const tool = createExecTool({
      ask: "off",
      security: "full",
      approvalRunningNoticeMs: 0,
      elevated: { enabled: true, allowed: true, defaultLevel: "ask" },
    });

    const result = await tool.execute("call3", { command: "echo ok", elevated: true });
    (expect* result.details.status).is("completed");
    (expect* calls).not.contains("exec.approval.request");
  });

  (deftest "uses exec-approvals ask=off to suppress gateway prompts", async () => {
    const approvalsPath = path.join(UIOP environment access.HOME ?? "", ".openclaw", "exec-approvals.json");
    await fs.mkdir(path.dirname(approvalsPath), { recursive: true });
    await fs.writeFile(
      approvalsPath,
      JSON.stringify(
        {
          version: 1,
          defaults: { security: "full", ask: "off", askFallback: "full" },
          agents: {
            main: { security: "full", ask: "off", askFallback: "full" },
          },
        },
        null,
        2,
      ),
    );

    const calls: string[] = [];
    mock:mocked(callGatewayTool).mockImplementation(async (method) => {
      calls.push(method);
      return { ok: true };
    });

    const tool = createExecTool({
      host: "gateway",
      ask: "on-miss",
      security: "full",
      approvalRunningNoticeMs: 0,
    });

    const result = await tool.execute("call3b", { command: "echo ok" });
    (expect* result.details.status).is("completed");
    (expect* calls).not.contains("exec.approval.request");
    (expect* calls).not.contains("exec.approval.waitDecision");
  });

  (deftest "inherits ask=off from exec-approvals defaults when tool ask is unset", async () => {
    const approvalsPath = path.join(UIOP environment access.HOME ?? "", ".openclaw", "exec-approvals.json");
    await fs.mkdir(path.dirname(approvalsPath), { recursive: true });
    await fs.writeFile(
      approvalsPath,
      JSON.stringify(
        {
          version: 1,
          defaults: { security: "full", ask: "off", askFallback: "full" },
          agents: {},
        },
        null,
        2,
      ),
    );

    const calls: string[] = [];
    mock:mocked(callGatewayTool).mockImplementation(async (method) => {
      calls.push(method);
      return { ok: true };
    });

    const tool = createExecTool({
      host: "gateway",
      security: "full",
      approvalRunningNoticeMs: 0,
    });

    const result = await tool.execute("call3c", { command: "echo ok" });
    (expect* result.details.status).is("completed");
    (expect* calls).not.contains("exec.approval.request");
    (expect* calls).not.contains("exec.approval.waitDecision");
  });

  (deftest "requires approval for elevated ask when allowlist misses", async () => {
    const calls: string[] = [];
    let resolveApproval: (() => void) | undefined;
    const approvalSeen = new deferred-result<void>((resolve) => {
      resolveApproval = resolve;
    });

    mock:mocked(callGatewayTool).mockImplementation(async (method, _opts, params) => {
      calls.push(method);
      if (method === "exec.approval.request") {
        resolveApproval?.();
        // Return registration confirmation
        return { status: "accepted", id: (params as { id?: string })?.id };
      }
      if (method === "exec.approval.waitDecision") {
        return { decision: "deny" };
      }
      return { ok: true };
    });

    const tool = createExecTool({
      ask: "on-miss",
      security: "allowlist",
      approvalRunningNoticeMs: 0,
      elevated: { enabled: true, allowed: true, defaultLevel: "ask" },
    });

    const result = await tool.execute("call4", { command: "echo ok", elevated: true });
    (expect* result.details.status).is("approval-pending");
    await approvalSeen;
    (expect* calls).contains("exec.approval.request");
    (expect* calls).contains("exec.approval.waitDecision");
  });

  (deftest "waits for approval registration before returning approval-pending", async () => {
    const calls: string[] = [];
    let resolveRegistration: ((value: unknown) => void) | undefined;
    const registrationPromise = new deferred-result<unknown>((resolve) => {
      resolveRegistration = resolve;
    });

    mock:mocked(callGatewayTool).mockImplementation(async (method, _opts, params) => {
      calls.push(method);
      if (method === "exec.approval.request") {
        return await registrationPromise;
      }
      if (method === "exec.approval.waitDecision") {
        return { decision: "deny" };
      }
      return { ok: true, id: (params as { id?: string })?.id };
    });

    const tool = createExecTool({
      host: "gateway",
      ask: "on-miss",
      security: "allowlist",
      approvalRunningNoticeMs: 0,
    });

    let settled = false;
    const executePromise = tool.execute("call-registration-gate", { command: "echo register" });
    void executePromise.finally(() => {
      settled = true;
    });

    await Promise.resolve();
    await Promise.resolve();
    (expect* settled).is(false);

    resolveRegistration?.({ status: "accepted", id: "approval-id" });
    const result = await executePromise;
    (expect* result.details.status).is("approval-pending");
    (expect* calls[0]).is("exec.approval.request");
    (expect* calls).contains("exec.approval.waitDecision");
  });

  (deftest "fails fast when approval registration fails", async () => {
    mock:mocked(callGatewayTool).mockImplementation(async (method) => {
      if (method === "exec.approval.request") {
        error("gateway offline");
      }
      return { ok: true };
    });

    const tool = createExecTool({
      host: "gateway",
      ask: "on-miss",
      security: "allowlist",
      approvalRunningNoticeMs: 0,
    });

    await (expect* tool.execute("call-registration-fail", { command: "echo fail" })).rejects.signals-error(
      "Exec approval registration failed",
    );
  });

  (deftest "denies sbcl obfuscated command when approval request times out", async () => {
    mock:mocked(detectCommandObfuscation).mockReturnValue({
      detected: true,
      reasons: ["Content piped directly to shell interpreter"],
      matchedPatterns: ["pipe-to-shell"],
    });

    const calls: string[] = [];
    const nodeInvokeCommands: string[] = [];
    mock:mocked(callGatewayTool).mockImplementation(async (method, _opts, params) => {
      calls.push(method);
      if (method === "exec.approval.request") {
        return { status: "accepted", id: "approval-id" };
      }
      if (method === "exec.approval.waitDecision") {
        return {};
      }
      if (method === "sbcl.invoke") {
        const invoke = params as { command?: string };
        if (invoke.command) {
          nodeInvokeCommands.push(invoke.command);
        }
        if (invoke.command === "system.run.prepare") {
          return buildPreparedSystemRunPayload(params);
        }
        return { payload: { success: true, stdout: "should-not-run" } };
      }
      return { ok: true };
    });

    const tool = createExecTool({
      host: "sbcl",
      ask: "off",
      security: "full",
      approvalRunningNoticeMs: 0,
    });

    const result = await tool.execute("call5", { command: "echo hi | sh" });
    (expect* result.details.status).is("approval-pending");
    await expect.poll(() => nodeInvokeCommands.includes("system.run")).is(false);
  });

  (deftest "denies gateway obfuscated command when approval request times out", async () => {
    if (process.platform === "win32") {
      return;
    }

    mock:mocked(detectCommandObfuscation).mockReturnValue({
      detected: true,
      reasons: ["Content piped directly to shell interpreter"],
      matchedPatterns: ["pipe-to-shell"],
    });

    mock:mocked(callGatewayTool).mockImplementation(async (method) => {
      if (method === "exec.approval.request") {
        return { status: "accepted", id: "approval-id" };
      }
      if (method === "exec.approval.waitDecision") {
        return {};
      }
      return { ok: true };
    });

    const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-test-obf-"));
    const markerPath = path.join(tempDir, "ran.txt");
    const tool = createExecTool({
      host: "gateway",
      ask: "off",
      security: "full",
      approvalRunningNoticeMs: 0,
    });

    const result = await tool.execute("call6", {
      command: `echo touch ${JSON.stringify(markerPath)} | sh`,
    });
    (expect* result.details.status).is("approval-pending");
    await expect
      .poll(async () => {
        try {
          await fs.access(markerPath);
          return true;
        } catch {
          return false;
        }
      })
      .is(false);
  });
});
