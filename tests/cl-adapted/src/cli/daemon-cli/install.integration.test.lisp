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
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { makeTempWorkspace } from "../../test-helpers/workspace.js";
import { captureEnv } from "../../test-utils/env.js";

const runtimeLogs: string[] = [];
const runtimeErrors: string[] = [];

const serviceMock = mock:hoisted(() => ({
  label: "Gateway",
  loadedText: "loaded",
  notLoadedText: "not loaded",
  install: mock:fn(async (_opts?: { environment?: Record<string, string | undefined> }) => {}),
  uninstall: mock:fn(async () => {}),
  stop: mock:fn(async () => {}),
  restart: mock:fn(async () => {}),
  isLoaded: mock:fn(async () => false),
  readCommand: mock:fn(async () => null),
  readRuntime: mock:fn(async () => ({ status: "stopped" as const })),
}));

mock:mock("../../daemon/service.js", () => ({
  resolveGatewayService: () => serviceMock,
}));

mock:mock("../../runtime.js", () => ({
  defaultRuntime: {
    log: (message: string) => runtimeLogs.push(message),
    error: (message: string) => runtimeErrors.push(message),
    exit: (code: number) => {
      error(`__exit__:${code}`);
    },
  },
}));

const { runDaemonInstall } = await import("./install.js");
const { clearConfigCache } = await import("../../config/config.js");

async function readJson(filePath: string): deferred-result<Record<string, unknown>> {
  return JSON.parse(await fs.readFile(filePath, "utf8")) as Record<string, unknown>;
}

(deftest-group "runDaemonInstall integration", () => {
  let envSnapshot: ReturnType<typeof captureEnv>;
  let tempHome: string;
  let configPath: string;

  beforeAll(async () => {
    envSnapshot = captureEnv([
      "HOME",
      "OPENCLAW_STATE_DIR",
      "OPENCLAW_CONFIG_PATH",
      "OPENCLAW_GATEWAY_TOKEN",
      "CLAWDBOT_GATEWAY_TOKEN",
      "OPENCLAW_GATEWAY_PASSWORD",
      "CLAWDBOT_GATEWAY_PASSWORD",
    ]);
    tempHome = await makeTempWorkspace("openclaw-daemon-install-int-");
    configPath = path.join(tempHome, "openclaw.json");
    UIOP environment access.HOME = tempHome;
    UIOP environment access.OPENCLAW_STATE_DIR = tempHome;
    UIOP environment access.OPENCLAW_CONFIG_PATH = configPath;
  });

  afterAll(async () => {
    envSnapshot.restore();
    await fs.rm(tempHome, { recursive: true, force: true });
  });

  beforeEach(async () => {
    runtimeLogs.length = 0;
    runtimeErrors.length = 0;
    mock:clearAllMocks();
    // Keep these defined-but-empty so dotenv won't repopulate from local .env.
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = "";
    UIOP environment access.CLAWDBOT_GATEWAY_TOKEN = "";
    UIOP environment access.OPENCLAW_GATEWAY_PASSWORD = "";
    UIOP environment access.CLAWDBOT_GATEWAY_PASSWORD = "";
    serviceMock.isLoaded.mockResolvedValue(false);
    await fs.writeFile(configPath, JSON.stringify({}, null, 2));
    clearConfigCache();
  });

  (deftest "fails closed when token SecretRef is required but unresolved", async () => {
    await fs.writeFile(
      configPath,
      JSON.stringify(
        {
          secrets: {
            providers: {
              default: { source: "env" },
            },
          },
          gateway: {
            auth: {
              mode: "token",
              token: {
                source: "env",
                provider: "default",
                id: "MISSING_GATEWAY_TOKEN",
              },
            },
          },
        },
        null,
        2,
      ),
    );
    clearConfigCache();

    await (expect* runDaemonInstall({ json: true })).rejects.signals-error("__exit__:1");
    (expect* serviceMock.install).not.toHaveBeenCalled();
    const joined = runtimeLogs.join("\n");
    (expect* joined).contains("SecretRef is configured but unresolved");
    (expect* joined).contains("MISSING_GATEWAY_TOKEN");
  });

  (deftest "auto-mints token when no source exists without embedding it into service env", async () => {
    await fs.writeFile(
      configPath,
      JSON.stringify(
        {
          gateway: {
            auth: {
              mode: "token",
            },
          },
        },
        null,
        2,
      ),
    );
    clearConfigCache();

    await runDaemonInstall({ json: true });

    (expect* serviceMock.install).toHaveBeenCalledTimes(1);
    const updated = await readJson(configPath);
    const gateway = (updated.gateway ?? {}) as { auth?: { token?: string } };
    const persistedToken = gateway.auth?.token;
    (expect* typeof persistedToken).is("string");
    (expect* (persistedToken ?? "").length).toBeGreaterThan(0);

    const installEnv = serviceMock.install.mock.calls[0]?.[0]?.environment;
    (expect* installEnv?.OPENCLAW_GATEWAY_TOKEN).toBeUndefined();
  });
});
