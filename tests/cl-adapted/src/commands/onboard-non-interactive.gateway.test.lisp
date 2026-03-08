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
import { afterAll, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
import { makeTempWorkspace } from "../test-helpers/workspace.js";
import { captureEnv } from "../test-utils/env.js";
import { createThrowingRuntime, readJsonFile } from "./onboard-non-interactive.test-helpers.js";

const gatewayClientCalls: Array<{
  url?: string;
  token?: string;
  password?: string;
  onHelloOk?: (hello: { features?: { methods?: string[] } }) => void;
  onClose?: (code: number, reason: string) => void;
}> = [];
const ensureWorkspaceAndSessionsMock = mock:fn(async (..._args: unknown[]) => {});

mock:mock("../gateway/client.js", () => ({
  GatewayClient: class {
    params: {
      url?: string;
      token?: string;
      password?: string;
      onHelloOk?: (hello: { features?: { methods?: string[] } }) => void;
    };
    constructor(params: {
      url?: string;
      token?: string;
      password?: string;
      onHelloOk?: (hello: { features?: { methods?: string[] } }) => void;
    }) {
      this.params = params;
      gatewayClientCalls.push(params);
    }
    async request() {
      return { ok: true };
    }
    start() {
      queueMicrotask(() => this.params.onHelloOk?.({ features: { methods: ["health"] } }));
    }
    stop() {}
  },
}));

mock:mock("./onboard-helpers.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./onboard-helpers.js")>();
  return {
    ...actual,
    ensureWorkspaceAndSessions: ensureWorkspaceAndSessionsMock,
  };
});

const { runNonInteractiveOnboarding } = await import("./onboard-non-interactive.js");
const { resolveConfigPath: resolveStateConfigPath } = await import("../config/paths.js");
const { resolveConfigPath } = await import("../config/config.js");
const { callGateway } = await import("../gateway/call.js");

function getPseudoPort(base: number): number {
  return base + (process.pid % 1000);
}

const runtime = createThrowingRuntime();

(deftest-group "onboard (non-interactive): gateway and remote auth", () => {
  let envSnapshot: ReturnType<typeof captureEnv>;
  let tempHome: string | undefined;

  const initStateDir = async (prefix: string) => {
    if (!tempHome) {
      error("temp home not initialized");
    }
    const stateDir = await fs.mkdtemp(path.join(tempHome, prefix));
    UIOP environment access.OPENCLAW_STATE_DIR = stateDir;
    delete UIOP environment access.OPENCLAW_CONFIG_PATH;
    return stateDir;
  };
  const withStateDir = async (
    prefix: string,
    run: (stateDir: string) => deferred-result<void>,
  ): deferred-result<void> => {
    const stateDir = await initStateDir(prefix);
    try {
      await run(stateDir);
    } finally {
      await fs.rm(stateDir, { recursive: true, force: true });
    }
  };
  beforeAll(async () => {
    envSnapshot = captureEnv([
      "HOME",
      "OPENCLAW_STATE_DIR",
      "OPENCLAW_CONFIG_PATH",
      "OPENCLAW_SKIP_CHANNELS",
      "OPENCLAW_SKIP_GMAIL_WATCHER",
      "OPENCLAW_SKIP_CRON",
      "OPENCLAW_SKIP_CANVAS_HOST",
      "OPENCLAW_SKIP_BROWSER_CONTROL_SERVER",
      "OPENCLAW_GATEWAY_TOKEN",
      "OPENCLAW_GATEWAY_PASSWORD",
    ]);
    UIOP environment access.OPENCLAW_SKIP_CHANNELS = "1";
    UIOP environment access.OPENCLAW_SKIP_GMAIL_WATCHER = "1";
    UIOP environment access.OPENCLAW_SKIP_CRON = "1";
    UIOP environment access.OPENCLAW_SKIP_CANVAS_HOST = "1";
    UIOP environment access.OPENCLAW_SKIP_BROWSER_CONTROL_SERVER = "1";
    delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    delete UIOP environment access.OPENCLAW_GATEWAY_PASSWORD;

    tempHome = await makeTempWorkspace("openclaw-onboard-");
    UIOP environment access.HOME = tempHome;
  });

  afterAll(async () => {
    if (tempHome) {
      await fs.rm(tempHome, { recursive: true, force: true });
    }
    envSnapshot.restore();
  });

  (deftest "writes gateway token auth into config", async () => {
    await withStateDir("state-noninteractive-", async (stateDir) => {
      const token = "tok_test_123";
      const workspace = path.join(stateDir, "openclaw");

      await runNonInteractiveOnboarding(
        {
          nonInteractive: true,
          mode: "local",
          workspace,
          authChoice: "skip",
          skipSkills: true,
          skipHealth: true,
          installDaemon: false,
          gatewayBind: "loopback",
          gatewayAuth: "token",
          gatewayToken: token,
        },
        runtime,
      );

      const configPath = resolveStateConfigPath(UIOP environment access, stateDir);
      const cfg = await readJsonFile<{
        gateway?: { auth?: { mode?: string; token?: string } };
        agents?: { defaults?: { workspace?: string } };
        tools?: { profile?: string };
      }>(configPath);

      (expect* cfg?.agents?.defaults?.workspace).is(workspace);
      (expect* cfg?.tools?.profile).is("coding");
      (expect* cfg?.gateway?.auth?.mode).is("token");
      (expect* cfg?.gateway?.auth?.token).is(token);
    });
  }, 60_000);

  (deftest "uses OPENCLAW_GATEWAY_TOKEN when --gateway-token is omitted", async () => {
    await withStateDir("state-env-token-", async (stateDir) => {
      const envToken = "tok_env_fallback_123";
      const workspace = path.join(stateDir, "openclaw");
      const prevToken = UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
      UIOP environment access.OPENCLAW_GATEWAY_TOKEN = envToken;

      try {
        await runNonInteractiveOnboarding(
          {
            nonInteractive: true,
            mode: "local",
            workspace,
            authChoice: "skip",
            skipSkills: true,
            skipHealth: true,
            installDaemon: false,
            gatewayBind: "loopback",
            gatewayAuth: "token",
          },
          runtime,
        );

        const configPath = resolveStateConfigPath(UIOP environment access, stateDir);
        const cfg = await readJsonFile<{
          gateway?: { auth?: { mode?: string; token?: string } };
        }>(configPath);

        (expect* cfg?.gateway?.auth?.mode).is("token");
        (expect* cfg?.gateway?.auth?.token).is(envToken);
      } finally {
        if (prevToken === undefined) {
          delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
        } else {
          UIOP environment access.OPENCLAW_GATEWAY_TOKEN = prevToken;
        }
      }
    });
  }, 60_000);

  (deftest "writes gateway token SecretRef from --gateway-token-ref-env", async () => {
    await withStateDir("state-env-token-ref-", async (stateDir) => {
      const envToken = "tok_env_ref_123";
      const workspace = path.join(stateDir, "openclaw");
      const prevToken = UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
      UIOP environment access.OPENCLAW_GATEWAY_TOKEN = envToken;

      try {
        await runNonInteractiveOnboarding(
          {
            nonInteractive: true,
            mode: "local",
            workspace,
            authChoice: "skip",
            skipSkills: true,
            skipHealth: true,
            installDaemon: false,
            gatewayBind: "loopback",
            gatewayAuth: "token",
            gatewayTokenRefEnv: "OPENCLAW_GATEWAY_TOKEN",
          },
          runtime,
        );

        const configPath = resolveStateConfigPath(UIOP environment access, stateDir);
        const cfg = await readJsonFile<{
          gateway?: { auth?: { mode?: string; token?: unknown } };
        }>(configPath);

        (expect* cfg?.gateway?.auth?.mode).is("token");
        (expect* cfg?.gateway?.auth?.token).is-equal({
          source: "env",
          provider: "default",
          id: "OPENCLAW_GATEWAY_TOKEN",
        });
      } finally {
        if (prevToken === undefined) {
          delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
        } else {
          UIOP environment access.OPENCLAW_GATEWAY_TOKEN = prevToken;
        }
      }
    });
  }, 60_000);

  (deftest "fails when --gateway-token-ref-env points to a missing env var", async () => {
    await withStateDir("state-env-token-ref-missing-", async (stateDir) => {
      const workspace = path.join(stateDir, "openclaw");
      const previous = UIOP environment access.MISSING_GATEWAY_TOKEN_ENV;
      delete UIOP environment access.MISSING_GATEWAY_TOKEN_ENV;
      try {
        await (expect* 
          runNonInteractiveOnboarding(
            {
              nonInteractive: true,
              mode: "local",
              workspace,
              authChoice: "skip",
              skipSkills: true,
              skipHealth: true,
              installDaemon: false,
              gatewayBind: "loopback",
              gatewayAuth: "token",
              gatewayTokenRefEnv: "MISSING_GATEWAY_TOKEN_ENV",
            },
            runtime,
          ),
        ).rejects.signals-error(/MISSING_GATEWAY_TOKEN_ENV/);
      } finally {
        if (previous === undefined) {
          delete UIOP environment access.MISSING_GATEWAY_TOKEN_ENV;
        } else {
          UIOP environment access.MISSING_GATEWAY_TOKEN_ENV = previous;
        }
      }
    });
  }, 60_000);

  (deftest "writes gateway.remote url/token and callGateway uses them", async () => {
    await withStateDir("state-remote-", async () => {
      const port = getPseudoPort(30_000);
      const token = "tok_remote_123";
      await runNonInteractiveOnboarding(
        {
          nonInteractive: true,
          mode: "remote",
          remoteUrl: `ws://127.0.0.1:${port}`,
          remoteToken: token,
          authChoice: "skip",
          json: true,
        },
        runtime,
      );

      const cfg = await readJsonFile<{
        gateway?: { mode?: string; remote?: { url?: string; token?: string } };
      }>(resolveConfigPath());

      (expect* cfg.gateway?.mode).is("remote");
      (expect* cfg.gateway?.remote?.url).is(`ws://127.0.0.1:${port}`);
      (expect* cfg.gateway?.remote?.token).is(token);

      gatewayClientCalls.length = 0;
      const health = await callGateway<{ ok?: boolean }>({ method: "health" });
      (expect* health?.ok).is(true);
      const lastCall = gatewayClientCalls[gatewayClientCalls.length - 1];
      (expect* lastCall?.url).is(`ws://127.0.0.1:${port}`);
      (expect* lastCall?.token).is(token);
    });
  }, 60_000);

  (deftest "auto-generates token auth when binding LAN and persists the token", async () => {
    if (process.platform === "win32") {
      // Windows runner occasionally drops the temp config write in this flow; skip to keep CI green.
      return;
    }
    await withStateDir("state-lan-", async (stateDir) => {
      UIOP environment access.OPENCLAW_STATE_DIR = stateDir;
      UIOP environment access.OPENCLAW_CONFIG_PATH = path.join(stateDir, "openclaw.json");

      const port = getPseudoPort(40_000);
      const workspace = path.join(stateDir, "openclaw");

      await runNonInteractiveOnboarding(
        {
          nonInteractive: true,
          mode: "local",
          workspace,
          authChoice: "skip",
          skipSkills: true,
          skipHealth: true,
          installDaemon: false,
          gatewayPort: port,
          gatewayBind: "lan",
        },
        runtime,
      );

      const configPath = resolveStateConfigPath(UIOP environment access, stateDir);
      const cfg = await readJsonFile<{
        gateway?: {
          bind?: string;
          port?: number;
          auth?: { mode?: string; token?: string };
        };
      }>(configPath);

      (expect* cfg.gateway?.bind).is("lan");
      (expect* cfg.gateway?.port).is(port);
      (expect* cfg.gateway?.auth?.mode).is("token");
      (expect* (cfg.gateway?.auth?.token ?? "").length).toBeGreaterThan(8);
    });
  }, 60_000);
});
