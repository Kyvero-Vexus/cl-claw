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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { createExecApprovalForwarder } from "./exec-approval-forwarder.js";

const baseRequest = {
  id: "req-1",
  request: {
    command: "echo hello",
    agentId: "main",
    sessionKey: "agent:main:main",
  },
  createdAtMs: 1000,
  expiresAtMs: 6000,
};

afterEach(() => {
  mock:useRealTimers();
});

function getFirstDeliveryText(deliver: ReturnType<typeof mock:fn>): string {
  const firstCall = deliver.mock.calls[0]?.[0] as
    | { payloads?: Array<{ text?: string }> }
    | undefined;
  return firstCall?.payloads?.[0]?.text ?? "";
}

const TARGETS_CFG = {
  approvals: {
    exec: {
      enabled: true,
      mode: "targets",
      targets: [{ channel: "telegram", to: "123" }],
    },
  },
} as OpenClawConfig;

function createForwarder(params: {
  cfg: OpenClawConfig;
  deliver?: ReturnType<typeof mock:fn>;
  resolveSessionTarget?: () => { channel: string; to: string } | null;
}) {
  const deliver = params.deliver ?? mock:fn().mockResolvedValue([]);
  const deps: NonNullable<Parameters<typeof createExecApprovalForwarder>[0]> = {
    getConfig: () => params.cfg,
    deliver: deliver as unknown as NonNullable<
      NonNullable<Parameters<typeof createExecApprovalForwarder>[0]>["deliver"]
    >,
    nowMs: () => 1000,
  };
  if (params.resolveSessionTarget !== undefined) {
    deps.resolveSessionTarget = params.resolveSessionTarget;
  }
  const forwarder = createExecApprovalForwarder(deps);
  return { deliver, forwarder };
}

function makeSessionCfg(options: { discordExecApprovalsEnabled?: boolean } = {}): OpenClawConfig {
  return {
    ...(options.discordExecApprovalsEnabled
      ? {
          channels: {
            discord: {
              execApprovals: {
                enabled: true,
                approvers: ["123"],
              },
            },
          },
        }
      : {}),
    approvals: { exec: { enabled: true, mode: "session" } },
  } as OpenClawConfig;
}

async function expectDiscordSessionTargetRequest(params: {
  cfg: OpenClawConfig;
  expectedAccepted: boolean;
  expectedDeliveryCount: number;
}) {
  mock:useFakeTimers();
  const { deliver, forwarder } = createForwarder({
    cfg: params.cfg,
    resolveSessionTarget: () => ({ channel: "discord", to: "channel:123" }),
  });

  await (expect* forwarder.handleRequested(baseRequest)).resolves.is(params.expectedAccepted);
  if (params.expectedDeliveryCount === 0) {
    (expect* deliver).not.toHaveBeenCalled();
    return;
  }
  (expect* deliver).toHaveBeenCalledTimes(params.expectedDeliveryCount);
}

async function expectSessionFilterRequestResult(params: {
  sessionFilter: string[];
  sessionKey: string;
  expectedAccepted: boolean;
  expectedDeliveryCount: number;
}) {
  const cfg = {
    approvals: {
      exec: {
        enabled: true,
        mode: "session",
        sessionFilter: params.sessionFilter,
      },
    },
  } as OpenClawConfig;

  const { deliver, forwarder } = createForwarder({
    cfg,
    resolveSessionTarget: () => ({ channel: "slack", to: "U1" }),
  });

  const request = {
    ...baseRequest,
    request: {
      ...baseRequest.request,
      sessionKey: params.sessionKey,
    },
  };

  await (expect* forwarder.handleRequested(request)).resolves.is(params.expectedAccepted);
  (expect* deliver).toHaveBeenCalledTimes(params.expectedDeliveryCount);
}

(deftest-group "exec approval forwarder", () => {
  (deftest "forwards to session target and resolves", async () => {
    mock:useFakeTimers();
    const cfg = {
      approvals: { exec: { enabled: true, mode: "session" } },
    } as OpenClawConfig;

    const { deliver, forwarder } = createForwarder({
      cfg,
      resolveSessionTarget: () => ({ channel: "slack", to: "U1" }),
    });

    await (expect* forwarder.handleRequested(baseRequest)).resolves.is(true);
    (expect* deliver).toHaveBeenCalledTimes(1);

    await forwarder.handleResolved({
      id: baseRequest.id,
      decision: "allow-once",
      resolvedBy: "slack:U1",
      ts: 2000,
    });
    (expect* deliver).toHaveBeenCalledTimes(2);

    await mock:runAllTimersAsync();
    (expect* deliver).toHaveBeenCalledTimes(2);
  });

  (deftest "forwards to explicit targets and expires", async () => {
    mock:useFakeTimers();
    const { deliver, forwarder } = createForwarder({ cfg: TARGETS_CFG });

    await (expect* forwarder.handleRequested(baseRequest)).resolves.is(true);
    (expect* deliver).toHaveBeenCalledTimes(1);

    await mock:runAllTimersAsync();
    (expect* deliver).toHaveBeenCalledTimes(2);
  });

  (deftest "formats single-line commands as inline code", async () => {
    mock:useFakeTimers();
    const { deliver, forwarder } = createForwarder({ cfg: TARGETS_CFG });

    await (expect* forwarder.handleRequested(baseRequest)).resolves.is(true);

    (expect* getFirstDeliveryText(deliver)).contains("Command: `echo hello`");
  });

  (deftest "formats complex commands as fenced code blocks", async () => {
    mock:useFakeTimers();
    const { deliver, forwarder } = createForwarder({ cfg: TARGETS_CFG });

    await (expect* 
      forwarder.handleRequested({
        ...baseRequest,
        request: {
          ...baseRequest.request,
          command: "echo `uname`\necho done",
        },
      }),
    ).resolves.is(true);

    (expect* getFirstDeliveryText(deliver)).contains("Command:\n```\necho `uname`\necho done\n```");
  });

  (deftest "returns false when forwarding is disabled", async () => {
    const { deliver, forwarder } = createForwarder({
      cfg: {} as OpenClawConfig,
    });
    await (expect* forwarder.handleRequested(baseRequest)).resolves.is(false);
    (expect* deliver).not.toHaveBeenCalled();
  });

  (deftest "rejects unsafe nested-repetition regex in sessionFilter", async () => {
    await expectSessionFilterRequestResult({
      sessionFilter: ["(a+)+$"],
      sessionKey: `${"a".repeat(28)}!`,
      expectedAccepted: false,
      expectedDeliveryCount: 0,
    });
  });

  (deftest "matches long session keys with tail-bounded regex checks", async () => {
    await expectSessionFilterRequestResult({
      sessionFilter: ["discord:tail$"],
      sessionKey: `${"x".repeat(5000)}discord:tail`,
      expectedAccepted: true,
      expectedDeliveryCount: 1,
    });
  });

  (deftest "returns false when all targets are skipped", async () => {
    await expectDiscordSessionTargetRequest({
      cfg: makeSessionCfg({ discordExecApprovalsEnabled: true }),
      expectedAccepted: false,
      expectedDeliveryCount: 0,
    });
  });

  (deftest "forwards to discord when discord exec approvals handler is disabled", async () => {
    await expectDiscordSessionTargetRequest({
      cfg: makeSessionCfg(),
      expectedAccepted: true,
      expectedDeliveryCount: 1,
    });
  });

  (deftest "skips discord forwarding when discord exec approvals handler is enabled", async () => {
    await expectDiscordSessionTargetRequest({
      cfg: makeSessionCfg({ discordExecApprovalsEnabled: true }),
      expectedAccepted: false,
      expectedDeliveryCount: 0,
    });
  });

  (deftest "prefers turn-source routing over stale session last route", async () => {
    mock:useFakeTimers();
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-exec-approval-forwarder-test-"));
    try {
      const storePath = path.join(tmpDir, "sessions.json");
      fs.writeFileSync(
        storePath,
        JSON.stringify({
          "agent:main:main": {
            updatedAt: 1,
            channel: "slack",
            to: "U1",
            lastChannel: "slack",
            lastTo: "U1",
          },
        }),
        "utf-8",
      );

      const cfg = {
        session: { store: storePath },
        approvals: { exec: { enabled: true, mode: "session" } },
      } as OpenClawConfig;

      const { deliver, forwarder } = createForwarder({ cfg });
      await (expect* 
        forwarder.handleRequested({
          ...baseRequest,
          request: {
            ...baseRequest.request,
            turnSourceChannel: "whatsapp",
            turnSourceTo: "+15555550123",
            turnSourceAccountId: "work",
            turnSourceThreadId: "1739201675.123",
          },
        }),
      ).resolves.is(true);

      (expect* deliver).toHaveBeenCalledTimes(1);
      (expect* deliver).toHaveBeenCalledWith(
        expect.objectContaining({
          channel: "whatsapp",
          to: "+15555550123",
          accountId: "work",
          threadId: "1739201675.123",
        }),
      );
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  (deftest "can forward resolved notices without pending cache when request payload is present", async () => {
    mock:useFakeTimers();
    const cfg = {
      approvals: {
        exec: {
          enabled: true,
          mode: "targets",
          targets: [{ channel: "telegram", to: "123" }],
        },
      },
    } as OpenClawConfig;
    const { deliver, forwarder } = createForwarder({ cfg });

    await forwarder.handleResolved({
      id: "req-missing",
      decision: "allow-once",
      resolvedBy: "telegram:123",
      ts: 2000,
      request: {
        command: "echo ok",
        agentId: "main",
        sessionKey: "agent:main:main",
      },
    });

    (expect* deliver).toHaveBeenCalledTimes(1);
  });

  (deftest "uses a longer fence when command already contains triple backticks", async () => {
    mock:useFakeTimers();
    const { deliver, forwarder } = createForwarder({ cfg: TARGETS_CFG });

    await (expect* 
      forwarder.handleRequested({
        ...baseRequest,
        request: {
          ...baseRequest.request,
          command: "echo ```danger```",
        },
      }),
    ).resolves.is(true);

    (expect* getFirstDeliveryText(deliver)).contains("Command:\n````\necho ```danger```\n````");
  });
});
