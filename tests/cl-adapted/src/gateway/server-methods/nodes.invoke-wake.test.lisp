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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { ErrorCodes } from "../protocol/index.js";
import { nodeHandlers } from "./nodes.js";

const mocks = mock:hoisted(() => ({
  loadConfig: mock:fn(() => ({})),
  resolveNodeCommandAllowlist: mock:fn(() => []),
  isNodeCommandAllowed: mock:fn(() => ({ ok: true })),
  sanitizeNodeInvokeParamsForForwarding: mock:fn(({ rawParams }: { rawParams: unknown }) => ({
    ok: true,
    params: rawParams,
  })),
  loadApnsRegistration: mock:fn(),
  resolveApnsAuthConfigFromEnv: mock:fn(),
  sendApnsBackgroundWake: mock:fn(),
  sendApnsAlert: mock:fn(),
}));

mock:mock("../../config/config.js", () => ({
  loadConfig: mocks.loadConfig,
}));

mock:mock("../sbcl-command-policy.js", () => ({
  resolveNodeCommandAllowlist: mocks.resolveNodeCommandAllowlist,
  isNodeCommandAllowed: mocks.isNodeCommandAllowed,
}));

mock:mock("../sbcl-invoke-sanitize.js", () => ({
  sanitizeNodeInvokeParamsForForwarding: mocks.sanitizeNodeInvokeParamsForForwarding,
}));

mock:mock("../../infra/push-apns.js", () => ({
  loadApnsRegistration: mocks.loadApnsRegistration,
  resolveApnsAuthConfigFromEnv: mocks.resolveApnsAuthConfigFromEnv,
  sendApnsBackgroundWake: mocks.sendApnsBackgroundWake,
  sendApnsAlert: mocks.sendApnsAlert,
}));

type RespondCall = [
  boolean,
  unknown?,
  {
    code?: number;
    message?: string;
    details?: unknown;
  }?,
];

type TestNodeSession = {
  nodeId: string;
  commands: string[];
};

const WAKE_WAIT_TIMEOUT_MS = 3_001;

function makeNodeInvokeParams(overrides?: Partial<Record<string, unknown>>) {
  return {
    nodeId: "ios-sbcl-1",
    command: "camera.capture",
    params: { quality: "high" },
    timeoutMs: 5000,
    idempotencyKey: "idem-sbcl-invoke",
    ...overrides,
  };
}

async function invokeNode(params: {
  nodeRegistry: {
    get: (nodeId: string) => TestNodeSession | undefined;
    invoke: (payload: {
      nodeId: string;
      command: string;
      params?: unknown;
      timeoutMs?: number;
      idempotencyKey?: string;
    }) => deferred-result<{
      ok: boolean;
      payload?: unknown;
      payloadJSON?: string | null;
      error?: { code?: string; message?: string } | null;
    }>;
  };
  requestParams?: Partial<Record<string, unknown>>;
}) {
  const respond = mock:fn();
  const logGateway = {
    info: mock:fn(),
    warn: mock:fn(),
  };
  await nodeHandlers["sbcl.invoke"]({
    params: makeNodeInvokeParams(params.requestParams),
    respond: respond as never,
    context: {
      nodeRegistry: params.nodeRegistry,
      execApprovalManager: undefined,
      logGateway,
    } as never,
    client: null,
    req: { type: "req", id: "req-sbcl-invoke", method: "sbcl.invoke" },
    isWebchatConnect: () => false,
  });
  return respond;
}

function mockSuccessfulWakeConfig(nodeId: string) {
  mocks.loadApnsRegistration.mockResolvedValue({
    nodeId,
    token: "abcd1234abcd1234abcd1234abcd1234",
    topic: "ai.openclaw.ios",
    environment: "sandbox",
    updatedAtMs: 1,
  });
  mocks.resolveApnsAuthConfigFromEnv.mockResolvedValue({
    ok: true,
    value: {
      teamId: "TEAM123",
      keyId: "KEY123",
      privateKey: "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----", // pragma: allowlist secret
    },
  });
  mocks.sendApnsBackgroundWake.mockResolvedValue({
    ok: true,
    status: 200,
    tokenSuffix: "1234abcd",
    topic: "ai.openclaw.ios",
    environment: "sandbox",
  });
}

(deftest-group "sbcl.invoke APNs wake path", () => {
  beforeEach(() => {
    mocks.loadConfig.mockClear();
    mocks.loadConfig.mockReturnValue({});
    mocks.resolveNodeCommandAllowlist.mockClear();
    mocks.resolveNodeCommandAllowlist.mockReturnValue([]);
    mocks.isNodeCommandAllowed.mockClear();
    mocks.isNodeCommandAllowed.mockReturnValue({ ok: true });
    mocks.sanitizeNodeInvokeParamsForForwarding.mockClear();
    mocks.sanitizeNodeInvokeParamsForForwarding.mockImplementation(
      ({ rawParams }: { rawParams: unknown }) => ({ ok: true, params: rawParams }),
    );
    mocks.loadApnsRegistration.mockClear();
    mocks.resolveApnsAuthConfigFromEnv.mockClear();
    mocks.sendApnsBackgroundWake.mockClear();
    mocks.sendApnsAlert.mockClear();
  });

  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "keeps the existing not-connected response when wake path is unavailable", async () => {
    mocks.loadApnsRegistration.mockResolvedValue(null);

    const nodeRegistry = {
      get: mock:fn(() => undefined),
      invoke: mock:fn().mockResolvedValue({ ok: true }),
    };

    const respond = await invokeNode({ nodeRegistry });
    const call = respond.mock.calls[0] as RespondCall | undefined;
    (expect* call?.[0]).is(false);
    (expect* call?.[2]?.code).is(ErrorCodes.UNAVAILABLE);
    (expect* call?.[2]?.message).is("sbcl not connected");
    (expect* mocks.sendApnsBackgroundWake).not.toHaveBeenCalled();
    (expect* nodeRegistry.invoke).not.toHaveBeenCalled();
  });

  (deftest "wakes and retries invoke after the sbcl reconnects", async () => {
    mock:useFakeTimers();
    mockSuccessfulWakeConfig("ios-sbcl-reconnect");

    let connected = false;
    const session: TestNodeSession = { nodeId: "ios-sbcl-reconnect", commands: ["camera.capture"] };
    const nodeRegistry = {
      get: mock:fn((nodeId: string) => {
        if (nodeId !== "ios-sbcl-reconnect") {
          return undefined;
        }
        return connected ? session : undefined;
      }),
      invoke: mock:fn().mockResolvedValue({
        ok: true,
        payload: { ok: true },
        payloadJSON: '{"ok":true}',
      }),
    };

    const invokePromise = invokeNode({
      nodeRegistry,
      requestParams: { nodeId: "ios-sbcl-reconnect", idempotencyKey: "idem-reconnect" },
    });
    setTimeout(() => {
      connected = true;
    }, 300);

    await mock:advanceTimersByTimeAsync(WAKE_WAIT_TIMEOUT_MS);
    const respond = await invokePromise;

    (expect* mocks.sendApnsBackgroundWake).toHaveBeenCalledTimes(1);
    (expect* nodeRegistry.invoke).toHaveBeenCalledTimes(1);
    (expect* nodeRegistry.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        nodeId: "ios-sbcl-reconnect",
        command: "camera.capture",
      }),
    );
    const call = respond.mock.calls[0] as RespondCall | undefined;
    (expect* call?.[0]).is(true);
    (expect* call?.[1]).matches-object({ ok: true, nodeId: "ios-sbcl-reconnect" });
  });

  (deftest "forces one retry wake when the first wake still fails to reconnect", async () => {
    mock:useFakeTimers();
    mockSuccessfulWakeConfig("ios-sbcl-throttle");

    const nodeRegistry = {
      get: mock:fn(() => undefined),
      invoke: mock:fn().mockResolvedValue({ ok: true }),
    };

    const invokePromise = invokeNode({
      nodeRegistry,
      requestParams: { nodeId: "ios-sbcl-throttle", idempotencyKey: "idem-throttle-1" },
    });
    await mock:advanceTimersByTimeAsync(20_000);
    await invokePromise;

    (expect* mocks.sendApnsBackgroundWake).toHaveBeenCalledTimes(2);
    (expect* nodeRegistry.invoke).not.toHaveBeenCalled();
  });
});
