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
import { ErrorCodes } from "../protocol/index.js";
import { pushHandlers } from "./push.js";

mock:mock("../../infra/push-apns.js", () => ({
  loadApnsRegistration: mock:fn(),
  normalizeApnsEnvironment: mock:fn(),
  resolveApnsAuthConfigFromEnv: mock:fn(),
  sendApnsAlert: mock:fn(),
}));

import {
  loadApnsRegistration,
  normalizeApnsEnvironment,
  resolveApnsAuthConfigFromEnv,
  sendApnsAlert,
} from "../../infra/push-apns.js";

type RespondCall = [boolean, unknown?, { code: number; message: string }?];

function createInvokeParams(params: Record<string, unknown>) {
  const respond = mock:fn();
  return {
    respond,
    invoke: async () =>
      await pushHandlers["push.test"]({
        params,
        respond: respond as never,
        context: {} as never,
        client: null,
        req: { type: "req", id: "req-1", method: "push.test" },
        isWebchatConnect: () => false,
      }),
  };
}

function expectInvalidRequestResponse(
  respond: ReturnType<typeof mock:fn>,
  expectedMessagePart: string,
) {
  const call = respond.mock.calls[0] as RespondCall | undefined;
  (expect* call?.[0]).is(false);
  (expect* call?.[2]?.code).is(ErrorCodes.INVALID_REQUEST);
  (expect* call?.[2]?.message).contains(expectedMessagePart);
}

(deftest-group "push.test handler", () => {
  beforeEach(() => {
    mock:mocked(loadApnsRegistration).mockClear();
    mock:mocked(normalizeApnsEnvironment).mockClear();
    mock:mocked(resolveApnsAuthConfigFromEnv).mockClear();
    mock:mocked(sendApnsAlert).mockClear();
  });

  (deftest "rejects invalid params", async () => {
    const { respond, invoke } = createInvokeParams({ title: "hello" });
    await invoke();
    expectInvalidRequestResponse(respond, "invalid push.test params");
  });

  (deftest "returns invalid request when sbcl has no APNs registration", async () => {
    mock:mocked(loadApnsRegistration).mockResolvedValue(null);
    const { respond, invoke } = createInvokeParams({ nodeId: "ios-sbcl-1" });
    await invoke();
    expectInvalidRequestResponse(respond, "has no APNs registration");
  });

  (deftest "sends push test when registration and auth are available", async () => {
    mock:mocked(loadApnsRegistration).mockResolvedValue({
      nodeId: "ios-sbcl-1",
      token: "abcd",
      topic: "ai.openclaw.ios",
      environment: "sandbox",
      updatedAtMs: 1,
    });
    mock:mocked(resolveApnsAuthConfigFromEnv).mockResolvedValue({
      ok: true,
      value: {
        teamId: "TEAM123",
        keyId: "KEY123",
        privateKey: "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----", // pragma: allowlist secret
      },
    });
    mock:mocked(normalizeApnsEnvironment).mockReturnValue(null);
    mock:mocked(sendApnsAlert).mockResolvedValue({
      ok: true,
      status: 200,
      tokenSuffix: "1234abcd",
      topic: "ai.openclaw.ios",
      environment: "sandbox",
    });

    const { respond, invoke } = createInvokeParams({
      nodeId: "ios-sbcl-1",
      title: "Wake",
      body: "Ping",
    });
    await invoke();

    (expect* sendApnsAlert).toHaveBeenCalledTimes(1);
    const call = respond.mock.calls[0] as RespondCall | undefined;
    (expect* call?.[0]).is(true);
    (expect* call?.[1]).matches-object({ ok: true, status: 200 });
  });
});
