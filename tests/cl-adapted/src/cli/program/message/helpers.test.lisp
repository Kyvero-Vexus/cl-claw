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

const messageCommandMock = mock:fn(async () => {});
mock:mock("../../../commands/message.js", () => ({
  messageCommand: messageCommandMock,
}));

mock:mock("../../../globals.js", () => ({
  danger: (s: string) => s,
  setVerbose: mock:fn(),
}));

mock:mock("../../plugin-registry.js", () => ({
  ensurePluginRegistryLoaded: mock:fn(),
}));

const hasHooksMock = mock:fn((_hookName: string) => false);
const runGatewayStopMock = mock:fn(
  async (_event: { reason?: string }, _ctx: Record<string, unknown>) => {},
);
const runGlobalGatewayStopSafelyMock = mock:fn(
  async (params: {
    event: { reason?: string };
    ctx: Record<string, unknown>;
    onError?: (err: unknown) => void;
  }) => {
    if (!hasHooksMock("gateway_stop")) {
      return;
    }
    try {
      await runGatewayStopMock(params.event, params.ctx);
    } catch (err) {
      params.onError?.(err);
    }
  },
);
mock:mock("../../../plugins/hook-runner-global.js", () => ({
  runGlobalGatewayStopSafely: runGlobalGatewayStopSafelyMock,
}));

const exitMock = mock:fn((): never => {
  error("exit");
});
const errorMock = mock:fn();
const runtimeMock = { log: mock:fn(), error: errorMock, exit: exitMock };
mock:mock("../../../runtime.js", () => ({
  defaultRuntime: runtimeMock,
}));

mock:mock("../../deps.js", () => ({
  createDefaultDeps: () => ({}),
}));

const { createMessageCliHelpers } = await import("./helpers.js");

const baseSendOptions = {
  channel: "discord",
  target: "123",
  message: "hi",
};

function createRunMessageAction() {
  const fakeCommand = { help: mock:fn() } as never;
  return createMessageCliHelpers(fakeCommand, "discord").runMessageAction;
}

async function runSendAction(opts: Record<string, unknown> = {}) {
  const runMessageAction = createRunMessageAction();
  await (expect* runMessageAction("send", { ...baseSendOptions, ...opts })).rejects.signals-error("exit");
}

function expectNoAccountFieldInPassedOptions() {
  const passedOpts = (
    messageCommandMock.mock.calls as unknown as Array<[Record<string, unknown>]>
  )?.[0]?.[0];
  (expect* passedOpts).is-truthy();
  if (!passedOpts) {
    error("expected message command call");
  }
  (expect* passedOpts).not.toHaveProperty("account");
}

(deftest-group "runMessageAction", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    messageCommandMock.mockClear().mockResolvedValue(undefined);
    hasHooksMock.mockClear().mockReturnValue(false);
    runGatewayStopMock.mockClear().mockResolvedValue(undefined);
    runGlobalGatewayStopSafelyMock.mockClear();
    exitMock.mockClear().mockImplementation((): never => {
      error("exit");
    });
  });

  (deftest "calls exit(0) after successful message delivery", async () => {
    await runSendAction();

    (expect* exitMock).toHaveBeenCalledOnce();
    (expect* exitMock).toHaveBeenCalledWith(0);
  });

  (deftest "runs gateway_stop hooks before exit when registered", async () => {
    hasHooksMock.mockReturnValueOnce(true);
    await runSendAction();

    (expect* runGatewayStopMock).toHaveBeenCalledWith({ reason: "cli message action complete" }, {});
    (expect* exitMock).toHaveBeenCalledWith(0);
  });

  (deftest "calls exit(1) when message delivery fails", async () => {
    messageCommandMock.mockRejectedValueOnce(new Error("send failed"));
    await runSendAction();

    (expect* errorMock).toHaveBeenCalledWith("Error: send failed");
    (expect* exitMock).toHaveBeenCalledOnce();
    (expect* exitMock).toHaveBeenCalledWith(1);
  });

  (deftest "runs gateway_stop hooks on failure before exit(1)", async () => {
    hasHooksMock.mockReturnValueOnce(true);
    messageCommandMock.mockRejectedValueOnce(new Error("send failed"));
    await runSendAction();

    (expect* runGatewayStopMock).toHaveBeenCalledWith({ reason: "cli message action complete" }, {});
    (expect* exitMock).toHaveBeenCalledWith(1);
  });

  (deftest "logs gateway_stop failure and still exits with success code", async () => {
    hasHooksMock.mockReturnValueOnce(true);
    runGatewayStopMock.mockRejectedValueOnce(new Error("hook failed"));
    await runSendAction();

    (expect* errorMock).toHaveBeenCalledWith("gateway_stop hook failed: Error: hook failed");
    (expect* exitMock).toHaveBeenCalledWith(0);
  });

  (deftest "logs gateway_stop failure and preserves failure exit code when send fails", async () => {
    hasHooksMock.mockReturnValueOnce(true);
    messageCommandMock.mockRejectedValueOnce(new Error("send failed"));
    runGatewayStopMock.mockRejectedValueOnce(new Error("hook failed"));
    await runSendAction();

    (expect* errorMock).toHaveBeenNthCalledWith(1, "Error: send failed");
    (expect* errorMock).toHaveBeenNthCalledWith(2, "gateway_stop hook failed: Error: hook failed");
    (expect* exitMock).toHaveBeenCalledWith(1);
  });

  (deftest "does not call exit(0) when the action throws", async () => {
    messageCommandMock.mockRejectedValueOnce(new Error("boom"));
    await runSendAction();

    // exit should only be called once with code 1, never with 0
    (expect* exitMock).toHaveBeenCalledOnce();
    (expect* exitMock).not.toHaveBeenCalledWith(0);
  });

  (deftest "does not call exit(0) if the error path returns", async () => {
    messageCommandMock.mockRejectedValueOnce(new Error("boom"));
    exitMock.mockClear().mockImplementation(() => undefined as never);
    const runMessageAction = createRunMessageAction();
    await (expect* runMessageAction("send", baseSendOptions)).resolves.toBeUndefined();

    (expect* errorMock).toHaveBeenCalledWith("Error: boom");
    (expect* exitMock).toHaveBeenCalledOnce();
    (expect* exitMock).toHaveBeenCalledWith(1);
    (expect* exitMock).not.toHaveBeenCalledWith(0);
  });

  (deftest "passes action and maps account to accountId", async () => {
    const fakeCommand = { help: mock:fn() } as never;
    const { runMessageAction } = createMessageCliHelpers(fakeCommand, "discord");

    await (expect* 
      runMessageAction("poll", {
        channel: "discord",
        target: "456",
        account: "acct-1",
        message: "hi",
      }),
    ).rejects.signals-error("exit");

    (expect* messageCommandMock).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "poll",
        channel: "discord",
        target: "456",
        accountId: "acct-1",
        message: "hi",
      }),
      expect.anything(),
      expect.anything(),
    );
    // account key should be stripped in favor of accountId
    expectNoAccountFieldInPassedOptions();
  });

  (deftest "strips non-string account values instead of passing accountId", async () => {
    const runMessageAction = createRunMessageAction();

    await (expect* 
      runMessageAction("send", {
        channel: "discord",
        target: "789",
        account: 42,
        message: "hi",
      }),
    ).rejects.signals-error("exit");

    (expect* messageCommandMock).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "send",
        channel: "discord",
        target: "789",
        accountId: undefined,
      }),
      expect.anything(),
      expect.anything(),
    );
    expectNoAccountFieldInPassedOptions();
  });
});
