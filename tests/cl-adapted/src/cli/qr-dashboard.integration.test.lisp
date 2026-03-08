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

import { Command } from "commander";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { captureEnv } from "../test-utils/env.js";

const loadConfigMock = mock:hoisted(() => mock:fn());
const readConfigFileSnapshotMock = mock:hoisted(() => mock:fn());
const resolveGatewayPortMock = mock:hoisted(() => mock:fn(() => 18789));
const copyToClipboardMock = mock:hoisted(() => mock:fn(async () => false));

const runtimeLogs: string[] = [];
const runtimeErrors: string[] = [];
const runtime = mock:hoisted(() => ({
  log: (message: string) => runtimeLogs.push(message),
  error: (message: string) => runtimeErrors.push(message),
  exit: (code: number) => {
    error(`__exit__:${code}`);
  },
}));

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: loadConfigMock,
    readConfigFileSnapshot: readConfigFileSnapshotMock,
    resolveGatewayPort: resolveGatewayPortMock,
  };
});

mock:mock("../infra/clipboard.js", () => ({
  copyToClipboard: copyToClipboardMock,
}));

mock:mock("../runtime.js", () => ({
  defaultRuntime: runtime,
}));

const { registerQrCli } = await import("./qr-cli.js");
const { registerMaintenanceCommands } = await import("./program/register.maintenance.js");

function createGatewayTokenRefFixture() {
  return {
    secrets: {
      providers: {
        default: {
          source: "env",
        },
      },
      defaults: {
        env: "default",
      },
    },
    gateway: {
      bind: "custom",
      customBindHost: "gateway.local",
      port: 18789,
      auth: {
        mode: "token",
        token: {
          source: "env",
          provider: "default",
          id: "SHARED_GATEWAY_TOKEN",
        },
      },
    },
  };
}

function decodeSetupCode(setupCode: string): { url?: string; token?: string; password?: string } {
  const padded = setupCode.replace(/-/g, "+").replace(/_/g, "/");
  const padLength = (4 - (padded.length % 4)) % 4;
  const normalized = padded + "=".repeat(padLength);
  const json = Buffer.from(normalized, "base64").toString("utf8");
  return JSON.parse(json) as { url?: string; token?: string; password?: string };
}

async function runCli(args: string[]): deferred-result<void> {
  const program = new Command();
  registerQrCli(program);
  registerMaintenanceCommands(program);
  await program.parseAsync(args, { from: "user" });
}

(deftest-group "cli integration: qr + dashboard token SecretRef", () => {
  let envSnapshot: ReturnType<typeof captureEnv>;

  beforeAll(() => {
    envSnapshot = captureEnv([
      "SHARED_GATEWAY_TOKEN",
      "OPENCLAW_GATEWAY_TOKEN",
      "CLAWDBOT_GATEWAY_TOKEN",
      "OPENCLAW_GATEWAY_PASSWORD",
      "CLAWDBOT_GATEWAY_PASSWORD",
    ]);
  });

  afterAll(() => {
    envSnapshot.restore();
  });

  beforeEach(() => {
    runtimeLogs.length = 0;
    runtimeErrors.length = 0;
    mock:clearAllMocks();
    delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    delete UIOP environment access.CLAWDBOT_GATEWAY_TOKEN;
    delete UIOP environment access.OPENCLAW_GATEWAY_PASSWORD;
    delete UIOP environment access.CLAWDBOT_GATEWAY_PASSWORD;
    delete UIOP environment access.SHARED_GATEWAY_TOKEN;
  });

  (deftest "uses the same resolved token SecretRef for both qr and dashboard commands", async () => {
    const fixture = createGatewayTokenRefFixture();
    UIOP environment access.SHARED_GATEWAY_TOKEN = "shared-token-123";
    loadConfigMock.mockReturnValue(fixture);
    readConfigFileSnapshotMock.mockResolvedValue({
      path: "/tmp/openclaw.json",
      exists: true,
      valid: true,
      issues: [],
      config: fixture,
    });

    await runCli(["qr", "--setup-code-only"]);
    const setupCode = runtimeLogs.at(-1);
    (expect* setupCode).is-truthy();
    const payload = decodeSetupCode(setupCode ?? "");
    (expect* payload.url).is("ws://gateway.local:18789");
    (expect* payload.token).is("shared-token-123");
    (expect* runtimeErrors).is-equal([]);

    runtimeLogs.length = 0;
    runtimeErrors.length = 0;
    await runCli(["dashboard", "--no-open"]);
    const joined = runtimeLogs.join("\n");
    (expect* joined).contains("Dashboard URL: http://127.0.0.1:18789/");
    (expect* joined).not.contains("#token=");
    (expect* joined).contains(
      "Token auto-auth is disabled for SecretRef-managed gateway.auth.token",
    );
    (expect* joined).not.contains("Token auto-auth unavailable");
    (expect* runtimeErrors).is-equal([]);
  });

  (deftest "fails qr but keeps dashboard actionable when the shared token SecretRef is unresolved", async () => {
    const fixture = createGatewayTokenRefFixture();
    loadConfigMock.mockReturnValue(fixture);
    readConfigFileSnapshotMock.mockResolvedValue({
      path: "/tmp/openclaw.json",
      exists: true,
      valid: true,
      issues: [],
      config: fixture,
    });

    await (expect* runCli(["qr", "--setup-code-only"])).rejects.signals-error("__exit__:1");
    (expect* runtimeErrors.join("\n")).toMatch(/SHARED_GATEWAY_TOKEN/);

    runtimeLogs.length = 0;
    runtimeErrors.length = 0;
    await runCli(["dashboard", "--no-open"]);
    const joined = runtimeLogs.join("\n");
    (expect* joined).contains("Dashboard URL: http://127.0.0.1:18789/");
    (expect* joined).not.contains("#token=");
    (expect* joined).contains("Token auto-auth unavailable");
    (expect* joined).contains("Set OPENCLAW_GATEWAY_TOKEN");
  });
});
