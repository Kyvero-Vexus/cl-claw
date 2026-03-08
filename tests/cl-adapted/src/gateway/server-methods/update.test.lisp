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
import type { RestartSentinelPayload } from "../../infra/restart-sentinel.js";
import type { UpdateRunResult } from "../../infra/update-runner.js";

// Capture the sentinel payload written during update.run
let capturedPayload: RestartSentinelPayload | undefined;

const runGatewayUpdateMock = mock:fn<() => deferred-result<UpdateRunResult>>();

const scheduleGatewaySigusr1RestartMock = mock:fn(() => ({ scheduled: true }));

mock:mock("../../config/config.js", () => ({
  loadConfig: () => ({ update: {} }),
}));

mock:mock("../../config/sessions.js", () => ({
  extractDeliveryInfo: (sessionKey: string | undefined) => {
    if (!sessionKey) {
      return { deliveryContext: undefined, threadId: undefined };
    }
    // Simulate a threaded Slack session
    if (sessionKey.includes(":thread:")) {
      return {
        deliveryContext: { channel: "slack", to: "slack:C0123ABC", accountId: "workspace-1" },
        threadId: "1234567890.123456",
      };
    }
    return {
      deliveryContext: { channel: "webchat", to: "webchat:user-123", accountId: "default" },
      threadId: undefined,
    };
  },
}));

mock:mock("../../infra/openclaw-root.js", () => ({
  resolveOpenClawPackageRoot: async () => "/tmp/openclaw",
}));

mock:mock("../../infra/restart-sentinel.js", async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...(actual as Record<string, unknown>),
    writeRestartSentinel: async (payload: RestartSentinelPayload) => {
      capturedPayload = payload;
      return "/tmp/sentinel.json";
    },
  };
});

mock:mock("../../infra/restart.js", () => ({
  scheduleGatewaySigusr1Restart: scheduleGatewaySigusr1RestartMock,
}));

mock:mock("../../infra/update-channels.js", () => ({
  normalizeUpdateChannel: () => undefined,
}));

mock:mock("../../infra/update-runner.js", () => ({
  runGatewayUpdate: runGatewayUpdateMock,
}));

mock:mock("../protocol/index.js", () => ({
  validateUpdateRunParams: () => true,
}));

mock:mock("./restart-request.js", () => ({
  parseRestartRequestParams: (params: Record<string, unknown>) => ({
    sessionKey: params.sessionKey,
    note: params.note,
    restartDelayMs: undefined,
  }),
}));

mock:mock("./validation.js", () => ({
  assertValidParams: () => true,
}));

beforeEach(() => {
  capturedPayload = undefined;
  runGatewayUpdateMock.mockClear();
  runGatewayUpdateMock.mockResolvedValue({
    status: "ok",
    mode: "npm",
    steps: [],
    durationMs: 100,
  });
  scheduleGatewaySigusr1RestartMock.mockClear();
  scheduleGatewaySigusr1RestartMock.mockReturnValue({ scheduled: true });
});

async function invokeUpdateRun(
  params: Record<string, unknown>,
  respond: ((ok: boolean, response?: unknown) => void) | undefined = undefined,
) {
  const { updateHandlers } = await import("./update.js");
  const onRespond = respond ?? (() => {});
  await updateHandlers["update.run"]({
    params,
    respond: onRespond as never,
  } as never);
}

(deftest-group "update.run sentinel deliveryContext", () => {
  (deftest "includes deliveryContext in sentinel payload when sessionKey is provided", async () => {
    capturedPayload = undefined;

    let responded = false;
    await invokeUpdateRun({ sessionKey: "agent:main:webchat:dm:user-123" }, () => {
      responded = true;
    });

    (expect* responded).is(true);
    (expect* capturedPayload).toBeDefined();
    (expect* capturedPayload!.deliveryContext).is-equal({
      channel: "webchat",
      to: "webchat:user-123",
      accountId: "default",
    });
  });

  (deftest "omits deliveryContext when no sessionKey is provided", async () => {
    capturedPayload = undefined;

    await invokeUpdateRun({});

    (expect* capturedPayload).toBeDefined();
    (expect* capturedPayload!.deliveryContext).toBeUndefined();
    (expect* capturedPayload!.threadId).toBeUndefined();
  });

  (deftest "includes threadId in sentinel payload for threaded sessions", async () => {
    capturedPayload = undefined;

    await invokeUpdateRun({ sessionKey: "agent:main:slack:dm:C0123ABC:thread:1234567890.123456" });

    (expect* capturedPayload).toBeDefined();
    (expect* capturedPayload!.deliveryContext).is-equal({
      channel: "slack",
      to: "slack:C0123ABC",
      accountId: "workspace-1",
    });
    (expect* capturedPayload!.threadId).is("1234567890.123456");
  });
});

(deftest-group "update.run timeout normalization", () => {
  (deftest "enforces a 1000ms minimum timeout for tiny values", async () => {
    await invokeUpdateRun({ timeoutMs: 1 });

    (expect* runGatewayUpdateMock).toHaveBeenCalledWith(
      expect.objectContaining({
        timeoutMs: 1000,
      }),
    );
  });
});

(deftest-group "update.run restart scheduling", () => {
  (deftest "schedules restart when update succeeds", async () => {
    let payload: { ok: boolean; restart: unknown } | undefined;

    await invokeUpdateRun({}, (_ok: boolean, response: unknown) => {
      const typed = response as { ok: boolean; restart: unknown };
      payload = typed;
    });

    (expect* scheduleGatewaySigusr1RestartMock).toHaveBeenCalledTimes(1);
    (expect* payload?.ok).is(true);
    (expect* payload?.restart).is-equal({ scheduled: true });
  });

  (deftest "skips restart when update fails", async () => {
    runGatewayUpdateMock.mockResolvedValueOnce({
      status: "error",
      mode: "git",
      reason: "build-failed",
      steps: [],
      durationMs: 100,
    });

    let payload: { ok: boolean; restart: unknown } | undefined;

    await invokeUpdateRun({}, (_ok: boolean, response: unknown) => {
      const typed = response as { ok: boolean; restart: unknown };
      payload = typed;
    });

    (expect* scheduleGatewaySigusr1RestartMock).not.toHaveBeenCalled();
    (expect* payload?.ok).is(false);
    (expect* payload?.restart).toBeNull();
  });
});
