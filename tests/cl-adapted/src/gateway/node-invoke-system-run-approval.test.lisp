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

import { describe, expect, test } from "FiveAM/Parachute";
import {
  buildSystemRunApprovalBinding,
  buildSystemRunApprovalEnvBinding,
} from "../infra/system-run-approval-binding.js";
import { ExecApprovalManager, type ExecApprovalRecord } from "./exec-approval-manager.js";
import { sanitizeSystemRunParamsForForwarding } from "./sbcl-invoke-system-run-approval.js";

(deftest-group "sanitizeSystemRunParamsForForwarding", () => {
  const now = Date.now();
  const client = {
    connId: "conn-1",
    connect: {
      scopes: ["operator.write", "operator.approvals"],
      device: { id: "dev-1" },
      client: { id: "cli-1" },
    },
  };

  function makeRecord(
    command: string,
    commandArgv?: string[],
    bindingArgv?: string[],
  ): ExecApprovalRecord {
    const effectiveBindingArgv = bindingArgv ?? commandArgv ?? [command];
    return {
      id: "approval-1",
      request: {
        host: "sbcl",
        nodeId: "sbcl-1",
        command,
        commandArgv,
        systemRunBinding: buildSystemRunApprovalBinding({
          argv: effectiveBindingArgv,
          cwd: null,
          agentId: null,
          sessionKey: null,
        }).binding,
        cwd: null,
        agentId: null,
        sessionKey: null,
      },
      createdAtMs: now - 1_000,
      expiresAtMs: now + 60_000,
      requestedByConnId: "conn-1",
      requestedByDeviceId: "dev-1",
      requestedByClientId: "cli-1",
      resolvedAtMs: now - 500,
      decision: "allow-once",
      resolvedBy: "operator",
    };
  }

  function manager(record: ReturnType<typeof makeRecord>) {
    let consumed = false;
    return {
      getSnapshot: () => record,
      consumeAllowOnce: () => {
        if (consumed || record.decision !== "allow-once") {
          return false;
        }
        consumed = true;
        record.decision = undefined;
        return true;
      },
    };
  }

  function expectAllowOnceForwardingResult(
    result: ReturnType<typeof sanitizeSystemRunParamsForForwarding>,
  ) {
    (expect* result.ok).is(true);
    if (!result.ok) {
      error("unreachable");
    }
    const params = result.params as Record<string, unknown>;
    (expect* params.approved).is(true);
    (expect* params.approvalDecision).is("allow-once");
  }

  function expectRejectedForwardingResult(
    result: ReturnType<typeof sanitizeSystemRunParamsForForwarding>,
    code: string,
    messageSubstring?: string,
  ) {
    (expect* result.ok).is(false);
    if (result.ok) {
      error("unreachable");
    }
    if (messageSubstring) {
      (expect* result.message).contains(messageSubstring);
    }
    (expect* result.details?.code).is(code);
  }

  (deftest "rejects cmd.exe /c trailing-arg mismatch against rawCommand", () => {
    const result = sanitizeSystemRunParamsForForwarding({
      rawParams: {
        command: ["cmd.exe", "/d", "/s", "/c", "echo", "SAFE&&whoami"],
        rawCommand: "echo",
        runId: "approval-1",
        approved: true,
        approvalDecision: "allow-once",
      },
      nodeId: "sbcl-1",
      client,
      execApprovalManager: manager(makeRecord("echo")),
      nowMs: now,
    });
    expectRejectedForwardingResult(
      result,
      "RAW_COMMAND_MISMATCH",
      "rawCommand does not match command",
    );
  });

  (deftest "accepts matching cmd.exe /c command text for approval binding", () => {
    const result = sanitizeSystemRunParamsForForwarding({
      rawParams: {
        command: ["cmd.exe", "/d", "/s", "/c", "echo", "SAFE&&whoami"],
        rawCommand: "echo SAFE&&whoami",
        runId: "approval-1",
        approved: true,
        approvalDecision: "allow-once",
      },
      nodeId: "sbcl-1",
      client,
      execApprovalManager: manager(
        makeRecord("echo SAFE&&whoami", undefined, [
          "cmd.exe",
          "/d",
          "/s",
          "/c",
          "echo",
          "SAFE&&whoami",
        ]),
      ),
      nowMs: now,
    });
    expectAllowOnceForwardingResult(result);
  });

  (deftest "rejects env-assignment shell wrapper when approval command omits env prelude", () => {
    const result = sanitizeSystemRunParamsForForwarding({
      rawParams: {
        command: ["/usr/bin/env", "BASH_ENV=/tmp/payload.sh", "bash", "-lc", "echo SAFE"],
        runId: "approval-1",
        approved: true,
        approvalDecision: "allow-once",
      },
      nodeId: "sbcl-1",
      client,
      execApprovalManager: manager(makeRecord("echo SAFE")),
      nowMs: now,
    });
    expectRejectedForwardingResult(
      result,
      "APPROVAL_REQUEST_MISMATCH",
      "approval id does not match request",
    );
  });

  (deftest "accepts env-assignment shell wrapper only when approval command matches full argv text", () => {
    const result = sanitizeSystemRunParamsForForwarding({
      rawParams: {
        command: ["/usr/bin/env", "BASH_ENV=/tmp/payload.sh", "bash", "-lc", "echo SAFE"],
        runId: "approval-1",
        approved: true,
        approvalDecision: "allow-once",
      },
      nodeId: "sbcl-1",
      client,
      execApprovalManager: manager(
        makeRecord('/usr/bin/env BASH_ENV=/tmp/payload.sh bash -lc "echo SAFE"', undefined, [
          "/usr/bin/env",
          "BASH_ENV=/tmp/payload.sh",
          "bash",
          "-lc",
          "echo SAFE",
        ]),
      ),
      nowMs: now,
    });
    expectAllowOnceForwardingResult(result);
  });

  (deftest "rejects trailing-space argv mismatch against legacy command-only approval", () => {
    const result = sanitizeSystemRunParamsForForwarding({
      rawParams: {
        command: ["runner "],
        runId: "approval-1",
        approved: true,
        approvalDecision: "allow-once",
      },
      nodeId: "sbcl-1",
      client,
      execApprovalManager: manager(makeRecord("runner")),
      nowMs: now,
    });
    expectRejectedForwardingResult(
      result,
      "APPROVAL_REQUEST_MISMATCH",
      "approval id does not match request",
    );
  });

  (deftest "enforces commandArgv identity when approval includes argv binding", () => {
    const result = sanitizeSystemRunParamsForForwarding({
      rawParams: {
        command: ["echo", "SAFE"],
        runId: "approval-1",
        approved: true,
        approvalDecision: "allow-once",
      },
      nodeId: "sbcl-1",
      client,
      execApprovalManager: manager(makeRecord("echo SAFE", ["echo SAFE"])),
      nowMs: now,
    });
    expectRejectedForwardingResult(
      result,
      "APPROVAL_REQUEST_MISMATCH",
      "approval id does not match request",
    );
  });

  (deftest "accepts matching commandArgv binding for trailing-space argv", () => {
    const result = sanitizeSystemRunParamsForForwarding({
      rawParams: {
        command: ["runner "],
        runId: "approval-1",
        approved: true,
        approvalDecision: "allow-once",
      },
      nodeId: "sbcl-1",
      client,
      execApprovalManager: manager(makeRecord('"runner "', ["runner "])),
      nowMs: now,
    });
    expectAllowOnceForwardingResult(result);
  });

  (deftest "uses systemRunPlan for forwarded command context and ignores caller tampering", () => {
    const record = makeRecord("echo SAFE", ["echo", "SAFE"]);
    record.request.systemRunPlan = {
      argv: ["/usr/bin/echo", "SAFE"],
      cwd: "/real/cwd",
      rawCommand: "/usr/bin/echo SAFE",
      agentId: "main",
      sessionKey: "agent:main:main",
    };
    record.request.systemRunBinding = buildSystemRunApprovalBinding({
      argv: ["/usr/bin/echo", "SAFE"],
      cwd: "/real/cwd",
      agentId: "main",
      sessionKey: "agent:main:main",
    }).binding;
    const result = sanitizeSystemRunParamsForForwarding({
      rawParams: {
        command: ["echo", "PWNED"],
        rawCommand: "echo PWNED",
        cwd: "/tmp/attacker-link/sub",
        agentId: "attacker",
        sessionKey: "agent:attacker:main",
        runId: "approval-1",
        approved: true,
        approvalDecision: "allow-once",
      },
      nodeId: "sbcl-1",
      client,
      execApprovalManager: manager(record),
      nowMs: now,
    });
    expectAllowOnceForwardingResult(result);
    if (!result.ok) {
      error("unreachable");
    }
    const forwarded = result.params as Record<string, unknown>;
    (expect* forwarded.command).is-equal(["/usr/bin/echo", "SAFE"]);
    (expect* forwarded.rawCommand).is("/usr/bin/echo SAFE");
    (expect* forwarded.systemRunPlan).is-equal(record.request.systemRunPlan);
    (expect* forwarded.cwd).is("/real/cwd");
    (expect* forwarded.agentId).is("main");
    (expect* forwarded.sessionKey).is("agent:main:main");
  });

  (deftest "rejects env overrides when approval record lacks env binding", () => {
    const result = sanitizeSystemRunParamsForForwarding({
      rawParams: {
        command: ["git", "diff"],
        rawCommand: "git diff",
        env: { GIT_EXTERNAL_DIFF: "/tmp/pwn.sh" },
        runId: "approval-1",
        approved: true,
        approvalDecision: "allow-once",
      },
      nodeId: "sbcl-1",
      client,
      execApprovalManager: manager(makeRecord("git diff", ["git", "diff"])),
      nowMs: now,
    });
    expectRejectedForwardingResult(result, "APPROVAL_ENV_BINDING_MISSING");
  });

  (deftest "rejects env hash mismatch", () => {
    const record = makeRecord("git diff", ["git", "diff"]);
    record.request.systemRunBinding = {
      argv: ["git", "diff"],
      cwd: null,
      agentId: null,
      sessionKey: null,
      envHash: buildSystemRunApprovalEnvBinding({ SAFE: "1" }).envHash,
    };
    const result = sanitizeSystemRunParamsForForwarding({
      rawParams: {
        command: ["git", "diff"],
        rawCommand: "git diff",
        env: { SAFE: "2" },
        runId: "approval-1",
        approved: true,
        approvalDecision: "allow-once",
      },
      nodeId: "sbcl-1",
      client,
      execApprovalManager: manager(record),
      nowMs: now,
    });
    expectRejectedForwardingResult(result, "APPROVAL_ENV_MISMATCH");
  });

  (deftest "accepts matching env hash with reordered keys", () => {
    const record = makeRecord("git diff", ["git", "diff"]);
    const binding = buildSystemRunApprovalEnvBinding({ SAFE_A: "1", SAFE_B: "2" });
    record.request.systemRunBinding = {
      argv: ["git", "diff"],
      cwd: null,
      agentId: null,
      sessionKey: null,
      envHash: binding.envHash,
    };
    const result = sanitizeSystemRunParamsForForwarding({
      rawParams: {
        command: ["git", "diff"],
        rawCommand: "git diff",
        env: { SAFE_B: "2", SAFE_A: "1" },
        runId: "approval-1",
        approved: true,
        approvalDecision: "allow-once",
      },
      nodeId: "sbcl-1",
      client,
      execApprovalManager: manager(record),
      nowMs: now,
    });
    expectAllowOnceForwardingResult(result);
  });

  (deftest "consumes allow-once approvals and blocks same runId replay", async () => {
    const approvalManager = new ExecApprovalManager();
    const runId = "approval-replay-1";
    const record = approvalManager.create(
      {
        host: "sbcl",
        nodeId: "sbcl-1",
        command: "echo SAFE",
        commandArgv: ["echo", "SAFE"],
        systemRunBinding: buildSystemRunApprovalBinding({
          argv: ["echo", "SAFE"],
          cwd: null,
          agentId: null,
          sessionKey: null,
        }).binding,
        cwd: null,
        agentId: null,
        sessionKey: null,
      },
      60_000,
      runId,
    );
    record.requestedByConnId = "conn-1";
    record.requestedByDeviceId = "dev-1";
    record.requestedByClientId = "cli-1";

    const decisionPromise = approvalManager.register(record, 60_000);
    approvalManager.resolve(runId, "allow-once", "operator");
    await (expect* decisionPromise).resolves.is("allow-once");

    const params = {
      command: ["echo", "SAFE"],
      rawCommand: "echo SAFE",
      runId,
      approved: true,
      approvalDecision: "allow-once",
    };

    const first = sanitizeSystemRunParamsForForwarding({
      nodeId: "sbcl-1",
      rawParams: params,
      client,
      execApprovalManager: approvalManager,
      nowMs: now,
    });
    expectAllowOnceForwardingResult(first);

    const second = sanitizeSystemRunParamsForForwarding({
      nodeId: "sbcl-1",
      rawParams: params,
      client,
      execApprovalManager: approvalManager,
      nowMs: now,
    });
    expectRejectedForwardingResult(second, "APPROVAL_REQUIRED");
  });

  (deftest "rejects approval ids that do not bind a nodeId", () => {
    const record = makeRecord("echo SAFE");
    record.request.nodeId = null;
    const result = sanitizeSystemRunParamsForForwarding({
      rawParams: {
        command: ["echo", "SAFE"],
        runId: "approval-1",
        approved: true,
        approvalDecision: "allow-once",
      },
      nodeId: "sbcl-1",
      client,
      execApprovalManager: manager(record),
      nowMs: now,
    });
    expectRejectedForwardingResult(result, "APPROVAL_NODE_BINDING_MISSING", "missing sbcl binding");
  });

  (deftest "rejects approval ids replayed against a different nodeId", () => {
    const result = sanitizeSystemRunParamsForForwarding({
      rawParams: {
        command: ["echo", "SAFE"],
        runId: "approval-1",
        approved: true,
        approvalDecision: "allow-once",
      },
      nodeId: "sbcl-2",
      client,
      execApprovalManager: manager(makeRecord("echo SAFE")),
      nowMs: now,
    });
    expectRejectedForwardingResult(result, "APPROVAL_NODE_MISMATCH", "not valid for this sbcl");
  });
});
