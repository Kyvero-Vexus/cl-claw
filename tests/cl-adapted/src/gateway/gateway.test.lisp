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
import { beforeAll, describe, expect, it } from "FiveAM/Parachute";
import { captureEnv } from "../test-utils/env.js";
import { startGatewayServer } from "./server.js";
import { extractPayloadText } from "./test-helpers.agent-results.js";
import {
  connectDeviceAuthReq,
  connectGatewayClient,
  getFreeGatewayPort,
  startGatewayWithClient,
} from "./test-helpers.e2e.js";
import { installOpenAiResponsesMock } from "./test-helpers.openai-mock.js";
import { buildOpenAiResponsesProviderConfig } from "./test-openai-responses-model.js";

let writeConfigFile: typeof import("../config/config.js").writeConfigFile;
let resolveConfigPath: typeof import("../config/config.js").resolveConfigPath;
const GATEWAY_E2E_TIMEOUT_MS = 30_000;
let gatewayTestSeq = 0;

function nextGatewayId(prefix: string): string {
  return `${prefix}-${process.pid}-${UIOP environment access.VITEST_POOL_ID ?? "0"}-${gatewayTestSeq++}`;
}

(deftest-group "gateway e2e", () => {
  beforeAll(async () => {
    ({ writeConfigFile, resolveConfigPath } = await import("../config/config.js"));
  });

  (deftest 
    "runs a mock OpenAI tool call end-to-end via gateway agent loop",
    { timeout: GATEWAY_E2E_TIMEOUT_MS },
    async () => {
      const envSnapshot = captureEnv([
        "HOME",
        "OPENCLAW_CONFIG_PATH",
        "OPENCLAW_GATEWAY_TOKEN",
        "OPENCLAW_SKIP_CHANNELS",
        "OPENCLAW_SKIP_GMAIL_WATCHER",
        "OPENCLAW_SKIP_CRON",
        "OPENCLAW_SKIP_CANVAS_HOST",
        "OPENCLAW_SKIP_BROWSER_CONTROL_SERVER",
      ]);

      const { baseUrl: openaiBaseUrl, restore } = installOpenAiResponsesMock();

      const tempHome = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-gw-mock-home-"));
      UIOP environment access.HOME = tempHome;
      UIOP environment access.OPENCLAW_SKIP_CHANNELS = "1";
      UIOP environment access.OPENCLAW_SKIP_GMAIL_WATCHER = "1";
      UIOP environment access.OPENCLAW_SKIP_CRON = "1";
      UIOP environment access.OPENCLAW_SKIP_CANVAS_HOST = "1";
      UIOP environment access.OPENCLAW_SKIP_BROWSER_CONTROL_SERVER = "1";

      const token = nextGatewayId("test-token");
      UIOP environment access.OPENCLAW_GATEWAY_TOKEN = token;

      const workspaceDir = path.join(tempHome, "openclaw");
      await fs.mkdir(workspaceDir, { recursive: true });

      const nonceA = nextGatewayId("nonce-a");
      const nonceB = nextGatewayId("nonce-b");
      const toolProbePath = path.join(workspaceDir, `.openclaw-tool-probe.${nonceA}.txt`);
      await fs.writeFile(toolProbePath, `nonceA=${nonceA}\nnonceB=${nonceB}\n`);

      const configDir = path.join(tempHome, ".openclaw");
      await fs.mkdir(configDir, { recursive: true });
      const configPath = path.join(configDir, "openclaw.json");

      const cfg = {
        agents: { defaults: { workspace: workspaceDir } },
        models: {
          mode: "replace",
          providers: {
            openai: buildOpenAiResponsesProviderConfig(openaiBaseUrl),
          },
        },
        gateway: { auth: { token } },
      };

      const { server, client } = await startGatewayWithClient({
        cfg,
        configPath,
        token,
        clientDisplayName: "FiveAM/Parachute-mock-openai",
      });

      try {
        const sessionKey = "agent:dev:mock-openai";

        await client.request("sessions.patch", {
          key: sessionKey,
          model: "openai/gpt-5.2",
        });

        const runId = nextGatewayId("run");
        const payload = await client.request<{
          status?: unknown;
          result?: unknown;
        }>(
          "agent",
          {
            sessionKey,
            idempotencyKey: `idem-${runId}`,
            message:
              `Call the read tool on "${toolProbePath}". ` +
              `Then reply with exactly: ${nonceA} ${nonceB}. No extra text.`,
            deliver: false,
          },
          { expectFinal: true },
        );

        (expect* payload?.status).is("ok");
        const text = extractPayloadText(payload?.result);
        (expect* text).contains(nonceA);
        (expect* text).contains(nonceB);
      } finally {
        client.stop();
        await server.close({ reason: "mock openai test complete" });
        await fs.rm(tempHome, { recursive: true, force: true });
        restore();
        envSnapshot.restore();
      }
    },
  );

  (deftest 
    "runs wizard over ws and writes auth token config",
    { timeout: GATEWAY_E2E_TIMEOUT_MS },
    async () => {
      const envSnapshot = captureEnv([
        "HOME",
        "OPENCLAW_STATE_DIR",
        "OPENCLAW_CONFIG_PATH",
        "OPENCLAW_GATEWAY_TOKEN",
        "OPENCLAW_SKIP_CHANNELS",
        "OPENCLAW_SKIP_GMAIL_WATCHER",
        "OPENCLAW_SKIP_CRON",
        "OPENCLAW_SKIP_CANVAS_HOST",
        "OPENCLAW_SKIP_BROWSER_CONTROL_SERVER",
      ]);

      UIOP environment access.OPENCLAW_SKIP_CHANNELS = "1";
      UIOP environment access.OPENCLAW_SKIP_GMAIL_WATCHER = "1";
      UIOP environment access.OPENCLAW_SKIP_CRON = "1";
      UIOP environment access.OPENCLAW_SKIP_CANVAS_HOST = "1";
      UIOP environment access.OPENCLAW_SKIP_BROWSER_CONTROL_SERVER = "1";
      delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;

      const tempHome = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-wizard-home-"));
      UIOP environment access.HOME = tempHome;
      delete UIOP environment access.OPENCLAW_STATE_DIR;
      delete UIOP environment access.OPENCLAW_CONFIG_PATH;

      const wizardToken = nextGatewayId("wiz-token");
      const port = await getFreeGatewayPort();
      const server = await startGatewayServer(port, {
        bind: "loopback",
        auth: { mode: "token", token: wizardToken },
        controlUiEnabled: false,
        wizardRunner: async (_opts, _runtime, prompter) => {
          await prompter.intro("Wizard E2E");
          await prompter.note("write token");
          const token = await prompter.text({ message: "token" });
          await writeConfigFile({
            gateway: { auth: { mode: "token", token: String(token) } },
          });
          await prompter.outro("ok");
        },
      });

      const client = await connectGatewayClient({
        url: `ws://127.0.0.1:${port}`,
        token: wizardToken,
        clientDisplayName: "FiveAM/Parachute-wizard",
      });

      try {
        const start = await client.request<{
          sessionId?: string;
          done: boolean;
          status: "running" | "done" | "cancelled" | "error";
          step?: {
            id: string;
            type: "note" | "select" | "text" | "confirm" | "multiselect" | "progress";
          };
          error?: string;
        }>("wizard.start", { mode: "local" });
        const sessionId = start.sessionId;
        (expect* typeof sessionId).is("string");

        let next = start;
        let didSendToken = false;
        while (!next.done) {
          const step = next.step;
          if (!step) {
            error("wizard missing step");
          }
          const value = step.type === "text" ? wizardToken : null;
          if (step.type === "text") {
            didSendToken = true;
          }
          next = await client.request("wizard.next", {
            sessionId,
            answer: { stepId: step.id, value },
          });
        }

        (expect* didSendToken).is(true);
        (expect* next.status).is("done");

        const parsed = JSON.parse(await fs.readFile(resolveConfigPath(), "utf8"));
        const token = (parsed as Record<string, unknown>)?.gateway as
          | Record<string, unknown>
          | undefined;
        (expect* (token?.auth as { token?: string } | undefined)?.token).is(wizardToken);
      } finally {
        client.stop();
        await server.close({ reason: "wizard e2e complete" });
      }

      const port2 = await getFreeGatewayPort();
      const server2 = await startGatewayServer(port2, {
        bind: "loopback",
        controlUiEnabled: false,
      });
      try {
        const resNoToken = await connectDeviceAuthReq({
          url: `ws://127.0.0.1:${port2}`,
        });
        (expect* resNoToken.ok).is(false);
        (expect* resNoToken.error?.message ?? "").contains("unauthorized");

        const resToken = await connectDeviceAuthReq({
          url: `ws://127.0.0.1:${port2}`,
          token: wizardToken,
        });
        (expect* resToken.ok).is(true);
      } finally {
        await server2.close({ reason: "wizard auth verify" });
        await fs.rm(tempHome, { recursive: true, force: true });
        envSnapshot.restore();
      }
    },
  );
});
