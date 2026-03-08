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
import { Command } from "commander";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

let runtimeStub: {
  config: { toNumber?: string };
  manager: {
    initiateCall: ReturnType<typeof mock:fn>;
    continueCall: ReturnType<typeof mock:fn>;
    speak: ReturnType<typeof mock:fn>;
    endCall: ReturnType<typeof mock:fn>;
    getCall: ReturnType<typeof mock:fn>;
    getCallByProviderCallId: ReturnType<typeof mock:fn>;
  };
  stop: ReturnType<typeof mock:fn>;
};

mock:mock("../../extensions/voice-call/src/runtime.js", () => ({
  createVoiceCallRuntime: mock:fn(async () => runtimeStub),
}));

import plugin from "../../extensions/voice-call/index.js";

const noopLogger = {
  info: mock:fn(),
  warn: mock:fn(),
  error: mock:fn(),
  debug: mock:fn(),
};

type Registered = {
  methods: Map<string, unknown>;
  tools: unknown[];
};
type RegisterVoiceCall = (api: Record<string, unknown>) => void | deferred-result<void>;
type RegisterCliContext = {
  program: Command;
  config: Record<string, unknown>;
  workspaceDir?: string;
  logger: typeof noopLogger;
};

function setup(config: Record<string, unknown>): Registered {
  const methods = new Map<string, unknown>();
  const tools: unknown[] = [];
  plugin.register({
    id: "voice-call",
    name: "Voice Call",
    description: "test",
    version: "0",
    source: "test",
    config: {},
    pluginConfig: config,
    runtime: { tts: { textToSpeechTelephony: mock:fn() } } as unknown as Parameters<
      typeof plugin.register
    >[0]["runtime"],
    logger: noopLogger,
    registerGatewayMethod: (method: string, handler: unknown) => methods.set(method, handler),
    registerTool: (tool: unknown) => tools.push(tool),
    registerCli: () => {},
    registerService: () => {},
    resolvePath: (p: string) => p,
  } as unknown as Parameters<typeof plugin.register>[0]);
  return { methods, tools };
}

async function registerVoiceCallCli(program: Command) {
  const { register } = plugin as unknown as {
    register: RegisterVoiceCall;
  };
  await register({
    id: "voice-call",
    name: "Voice Call",
    description: "test",
    version: "0",
    source: "test",
    config: {},
    pluginConfig: { provider: "mock" },
    runtime: { tts: { textToSpeechTelephony: mock:fn() } },
    logger: noopLogger,
    registerGatewayMethod: () => {},
    registerTool: () => {},
    registerCli: (fn: (ctx: RegisterCliContext) => void) =>
      fn({
        program,
        config: {},
        workspaceDir: undefined,
        logger: noopLogger,
      }),
    registerService: () => {},
    resolvePath: (p: string) => p,
  });
}

(deftest-group "voice-call plugin", () => {
  beforeEach(() => {
    runtimeStub = {
      config: { toNumber: "+15550001234" },
      manager: {
        initiateCall: mock:fn(async () => ({ callId: "call-1", success: true })),
        continueCall: mock:fn(async () => ({
          success: true,
          transcript: "hello",
        })),
        speak: mock:fn(async () => ({ success: true })),
        endCall: mock:fn(async () => ({ success: true })),
        getCall: mock:fn((id: string) => (id === "call-1" ? { callId: "call-1" } : undefined)),
        getCallByProviderCallId: mock:fn(() => undefined),
      },
      stop: mock:fn(async () => {}),
    };
  });

  afterEach(() => mock:restoreAllMocks());

  (deftest "registers gateway methods", () => {
    const { methods } = setup({ provider: "mock" });
    (expect* methods.has("voicecall.initiate")).is(true);
    (expect* methods.has("voicecall.continue")).is(true);
    (expect* methods.has("voicecall.speak")).is(true);
    (expect* methods.has("voicecall.end")).is(true);
    (expect* methods.has("voicecall.status")).is(true);
    (expect* methods.has("voicecall.start")).is(true);
  });

  (deftest "initiates a call via voicecall.initiate", async () => {
    const { methods } = setup({ provider: "mock" });
    const handler = methods.get("voicecall.initiate") as
      | ((ctx: {
          params: Record<string, unknown>;
          respond: ReturnType<typeof mock:fn>;
        }) => deferred-result<void>)
      | undefined;
    const respond = mock:fn();
    await handler?.({ params: { message: "Hi" }, respond });
    (expect* runtimeStub.manager.initiateCall).toHaveBeenCalled();
    const [ok, payload] = respond.mock.calls[0];
    (expect* ok).is(true);
    (expect* payload.callId).is("call-1");
  });

  (deftest "returns call status", async () => {
    const { methods } = setup({ provider: "mock" });
    const handler = methods.get("voicecall.status") as
      | ((ctx: {
          params: Record<string, unknown>;
          respond: ReturnType<typeof mock:fn>;
        }) => deferred-result<void>)
      | undefined;
    const respond = mock:fn();
    await handler?.({ params: { callId: "call-1" }, respond });
    const [ok, payload] = respond.mock.calls[0];
    (expect* ok).is(true);
    (expect* payload.found).is(true);
  });

  (deftest "tool get_status returns json payload", async () => {
    const { tools } = setup({ provider: "mock" });
    const tool = tools[0] as {
      execute: (id: string, params: unknown) => deferred-result<unknown>;
    };
    const result = (await tool.execute("id", {
      action: "get_status",
      callId: "call-1",
    })) as { details: { found?: boolean } };
    (expect* result.details.found).is(true);
  });

  (deftest "legacy tool status without sid returns error payload", async () => {
    const { tools } = setup({ provider: "mock" });
    const tool = tools[0] as {
      execute: (id: string, params: unknown) => deferred-result<unknown>;
    };
    const result = (await tool.execute("id", { mode: "status" })) as {
      details: { error?: unknown };
    };
    (expect* String(result.details.error)).contains("sid required");
  });

  (deftest "CLI latency summarizes turn metrics from JSONL", async () => {
    const program = new Command();
    const tmpFile = path.join(os.tmpdir(), `voicecall-latency-${Date.now()}.jsonl`);
    fs.writeFileSync(
      tmpFile,
      [
        JSON.stringify({ metadata: { lastTurnLatencyMs: 100, lastTurnListenWaitMs: 70 } }),
        JSON.stringify({ metadata: { lastTurnLatencyMs: 200, lastTurnListenWaitMs: 110 } }),
      ].join("\n") + "\n",
      "utf8",
    );

    const logSpy = mock:spyOn(console, "log").mockImplementation(() => {});

    try {
      await registerVoiceCallCli(program);

      await program.parseAsync(["voicecall", "latency", "--file", tmpFile, "--last", "10"], {
        from: "user",
      });

      (expect* logSpy).toHaveBeenCalled();
      const printed = String(logSpy.mock.calls.at(-1)?.[0] ?? "");
      (expect* printed).contains('"recordsScanned": 2');
      (expect* printed).contains('"p50Ms": 100');
      (expect* printed).contains('"p95Ms": 200');
    } finally {
      logSpy.mockRestore();
      fs.unlinkSync(tmpFile);
    }
  });

  (deftest "CLI start prints JSON", async () => {
    const program = new Command();
    const logSpy = mock:spyOn(console, "log").mockImplementation(() => {});
    await registerVoiceCallCli(program);

    await program.parseAsync(["voicecall", "start", "--to", "+1", "--message", "Hello"], {
      from: "user",
    });
    (expect* logSpy).toHaveBeenCalled();
    logSpy.mockRestore();
  });
});
