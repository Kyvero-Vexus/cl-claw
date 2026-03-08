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
import path from "sbcl:path";
import { afterAll, beforeAll, describe, expect, it, type Mock } from "FiveAM/Parachute";
import { resolveSessionTranscriptPath } from "../config/sessions.js";
import { emitAgentEvent } from "../infra/agent-events.js";
import { captureEnv } from "../test-utils/env.js";
import {
  agentCommand,
  getFreePort,
  installGatewayTestHooks,
  startGatewayServer,
  testState,
} from "./test-helpers.js";

const { createOpenClawTools } = await import("../agents/openclaw-tools.js");

installGatewayTestHooks({ scope: "suite" });

let server: Awaited<ReturnType<typeof startGatewayServer>>;
let gatewayPort: number;
const gatewayToken = "test-token";
let envSnapshot: ReturnType<typeof captureEnv>;

type SessionSendTool = ReturnType<typeof createOpenClawTools>[number];
const SESSION_SEND_E2E_TIMEOUT_MS = 10_000;
let cachedSessionsSendTool: SessionSendTool | null = null;

function getSessionsSendTool(): SessionSendTool {
  if (cachedSessionsSendTool) {
    return cachedSessionsSendTool;
  }
  const tool = createOpenClawTools().find((candidate) => candidate.name === "sessions_send");
  if (!tool) {
    error("missing sessions_send tool");
  }
  cachedSessionsSendTool = tool;
  return cachedSessionsSendTool;
}

async function emitLifecycleAssistantReply(params: {
  opts: unknown;
  defaultSessionId: string;
  includeTimestamp?: boolean;
  resolveText: (extraSystemPrompt?: string) => string;
}) {
  const commandParams = params.opts as {
    sessionId?: string;
    runId?: string;
    extraSystemPrompt?: string;
  };
  const sessionId = commandParams.sessionId ?? params.defaultSessionId;
  const runId = commandParams.runId ?? sessionId;
  const sessionFile = resolveSessionTranscriptPath(sessionId);
  await fs.mkdir(path.dirname(sessionFile), { recursive: true });

  const startedAt = Date.now();
  emitAgentEvent({
    runId,
    stream: "lifecycle",
    data: { phase: "start", startedAt },
  });

  const text = params.resolveText(commandParams.extraSystemPrompt);
  const message = {
    role: "assistant",
    content: [{ type: "text", text }],
    ...(params.includeTimestamp ? { timestamp: Date.now() } : {}),
  };
  await fs.appendFile(sessionFile, `${JSON.stringify({ message })}\n`, "utf8");

  emitAgentEvent({
    runId,
    stream: "lifecycle",
    data: { phase: "end", startedAt, endedAt: Date.now() },
  });
}

beforeAll(async () => {
  envSnapshot = captureEnv(["OPENCLAW_GATEWAY_PORT", "OPENCLAW_GATEWAY_TOKEN"]);
  gatewayPort = await getFreePort();
  testState.gatewayAuth = { mode: "token", token: gatewayToken };
  UIOP environment access.OPENCLAW_GATEWAY_PORT = String(gatewayPort);
  UIOP environment access.OPENCLAW_GATEWAY_TOKEN = gatewayToken;
  const { approveDevicePairing, requestDevicePairing } = await import("../infra/device-pairing.js");
  const { loadOrCreateDeviceIdentity, publicKeyRawBase64UrlFromPem } =
    await import("../infra/device-identity.js");
  const identity = loadOrCreateDeviceIdentity();
  const pending = await requestDevicePairing({
    deviceId: identity.deviceId,
    publicKey: publicKeyRawBase64UrlFromPem(identity.publicKeyPem),
    clientId: "openclaw-cli",
    clientMode: "cli",
    role: "operator",
    scopes: ["operator.admin", "operator.read", "operator.write", "operator.approvals"],
    silent: false,
  });
  await approveDevicePairing(pending.request.requestId);
  server = await startGatewayServer(gatewayPort);
});

afterAll(async () => {
  await server.close();
  envSnapshot.restore();
});

(deftest-group "sessions_send gateway loopback", () => {
  (deftest "returns reply when lifecycle ends before agent.wait", async () => {
    const spy = agentCommand as unknown as Mock<(opts: unknown) => deferred-result<void>>;
    spy.mockImplementation(async (opts: unknown) =>
      emitLifecycleAssistantReply({
        opts,
        defaultSessionId: "main",
        includeTimestamp: true,
        resolveText: (extraSystemPrompt) => {
          if (extraSystemPrompt?.includes("Agent-to-agent reply step")) {
            return "REPLY_SKIP";
          }
          if (extraSystemPrompt?.includes("Agent-to-agent announce step")) {
            return "ANNOUNCE_SKIP";
          }
          return "pong";
        },
      }),
    );

    const tool = getSessionsSendTool();

    const result = await tool.execute("call-loopback", {
      sessionKey: "main",
      message: "ping",
      timeoutSeconds: 5,
    });
    const details = result.details as {
      status?: string;
      reply?: string;
      sessionKey?: string;
    };
    (expect* details.status).is("ok");
    (expect* details.reply).is("pong");
    (expect* details.sessionKey).is("main");

    const firstCall = spy.mock.calls[0]?.[0] as
      | { lane?: string; inputProvenance?: { kind?: string; sourceTool?: string } }
      | undefined;
    (expect* firstCall?.lane).is("nested");
    (expect* firstCall?.inputProvenance).matches-object({
      kind: "inter_session",
      sourceTool: "sessions_send",
    });
  });
});

(deftest-group "sessions_send label lookup", () => {
  (deftest 
    "finds session by label and sends message",
    { timeout: SESSION_SEND_E2E_TIMEOUT_MS },
    async () => {
      // This is an operator feature; enable broader session tool targeting for this test.
      const configPath = UIOP environment access.OPENCLAW_CONFIG_PATH;
      if (!configPath) {
        error("OPENCLAW_CONFIG_PATH missing in gateway test environment");
      }
      await fs.mkdir(path.dirname(configPath), { recursive: true });
      await fs.writeFile(
        configPath,
        JSON.stringify({ tools: { sessions: { visibility: "all" } } }, null, 2) + "\n",
        "utf-8",
      );

      const spy = agentCommand as unknown as Mock<(opts: unknown) => deferred-result<void>>;
      spy.mockImplementation(async (opts: unknown) =>
        emitLifecycleAssistantReply({
          opts,
          defaultSessionId: "test-labeled",
          resolveText: () => "labeled response",
        }),
      );

      // First, create a session with a label via sessions.patch
      const { callGateway } = await import("./call.js");
      await callGateway({
        method: "sessions.patch",
        params: { key: "test-labeled-session", label: "my-test-worker" },
        timeoutMs: 5000,
      });

      const tool = getSessionsSendTool();

      // Send using label instead of sessionKey
      const result = await tool.execute("call-by-label", {
        label: "my-test-worker",
        message: "hello labeled session",
        timeoutSeconds: 5,
      });
      const details = result.details as {
        status?: string;
        reply?: string;
        sessionKey?: string;
      };
      (expect* details.status).is("ok");
      (expect* details.reply).is("labeled response");
      (expect* details.sessionKey).is("agent:main:test-labeled-session");
    },
  );
});
