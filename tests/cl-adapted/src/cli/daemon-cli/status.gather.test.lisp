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
import { captureEnv } from "../../test-utils/env.js";

const callGatewayStatusProbe = mock:fn(async (_opts?: unknown) => ({ ok: true as const }));
const loadGatewayTlsRuntime = mock:fn(async (_cfg?: unknown) => ({
  enabled: true,
  required: true,
  fingerprintSha256: "sha256:11:22:33:44",
}));
const findExtraGatewayServices = mock:fn(async (_env?: unknown, _opts?: unknown) => []);
const inspectPortUsage = mock:fn(async (port: number) => ({
  port,
  status: "free" as const,
  listeners: [],
  hints: [],
}));
const readLastGatewayErrorLine = mock:fn(async (_env?: NodeJS.ProcessEnv) => null);
const auditGatewayServiceConfig = mock:fn(async (_opts?: unknown) => undefined);
const serviceIsLoaded = mock:fn(async (_opts?: unknown) => true);
const serviceReadRuntime = mock:fn(async (_env?: NodeJS.ProcessEnv) => ({ status: "running" }));
const serviceReadCommand = mock:fn(async (_env?: NodeJS.ProcessEnv) => ({
  programArguments: ["/bin/sbcl", "cli", "gateway", "--port", "19001"],
  environment: {
    OPENCLAW_STATE_DIR: "/tmp/openclaw-daemon",
    OPENCLAW_CONFIG_PATH: "/tmp/openclaw-daemon/openclaw.json",
  },
}));
const resolveGatewayBindHost = mock:fn(
  async (_bindMode?: string, _customBindHost?: string) => "0.0.0.0",
);
const pickPrimaryTailnetIPv4 = mock:fn(() => "100.64.0.9");
const resolveGatewayPort = mock:fn((_cfg?: unknown, _env?: unknown) => 18789);
const resolveStateDir = mock:fn(
  (env: NodeJS.ProcessEnv) => env.OPENCLAW_STATE_DIR ?? "/tmp/openclaw-cli",
);
const resolveConfigPath = mock:fn((env: NodeJS.ProcessEnv, stateDir: string) => {
  return env.OPENCLAW_CONFIG_PATH ?? `${stateDir}/openclaw.json`;
});
let daemonLoadedConfig: Record<string, unknown> = {
  gateway: {
    bind: "lan",
    tls: { enabled: true },
    auth: { token: "daemon-token" },
  },
};
let cliLoadedConfig: Record<string, unknown> = {
  gateway: {
    bind: "loopback",
  },
};

mock:mock("../../config/config.js", () => ({
  createConfigIO: ({ configPath }: { configPath: string }) => {
    const isDaemon = configPath.includes("/openclaw-daemon/");
    return {
      readConfigFileSnapshot: async () => ({
        path: configPath,
        exists: true,
        valid: true,
        issues: [],
      }),
      loadConfig: () => (isDaemon ? daemonLoadedConfig : cliLoadedConfig),
    };
  },
  resolveConfigPath: (env: NodeJS.ProcessEnv, stateDir: string) => resolveConfigPath(env, stateDir),
  resolveGatewayPort: (cfg?: unknown, env?: unknown) => resolveGatewayPort(cfg, env),
  resolveStateDir: (env: NodeJS.ProcessEnv) => resolveStateDir(env),
}));

mock:mock("../../daemon/diagnostics.js", () => ({
  readLastGatewayErrorLine: (env: NodeJS.ProcessEnv) => readLastGatewayErrorLine(env),
}));

mock:mock("../../daemon/inspect.js", () => ({
  findExtraGatewayServices: (env: unknown, opts?: unknown) => findExtraGatewayServices(env, opts),
}));

mock:mock("../../daemon/service-audit.js", () => ({
  auditGatewayServiceConfig: (opts: unknown) => auditGatewayServiceConfig(opts),
}));

mock:mock("../../daemon/service.js", () => ({
  resolveGatewayService: () => ({
    label: "LaunchAgent",
    loadedText: "loaded",
    notLoadedText: "not loaded",
    isLoaded: serviceIsLoaded,
    readCommand: serviceReadCommand,
    readRuntime: serviceReadRuntime,
  }),
}));

mock:mock("../../gateway/net.js", () => ({
  resolveGatewayBindHost: (bindMode: string, customBindHost?: string) =>
    resolveGatewayBindHost(bindMode, customBindHost),
}));

mock:mock("../../infra/ports.js", () => ({
  inspectPortUsage: (port: number) => inspectPortUsage(port),
  formatPortDiagnostics: () => [],
}));

mock:mock("../../infra/tailnet.js", () => ({
  pickPrimaryTailnetIPv4: () => pickPrimaryTailnetIPv4(),
}));

mock:mock("../../infra/tls/gateway.js", () => ({
  loadGatewayTlsRuntime: (cfg: unknown) => loadGatewayTlsRuntime(cfg),
}));

mock:mock("./probe.js", () => ({
  probeGatewayStatus: (opts: unknown) => callGatewayStatusProbe(opts),
}));

const { gatherDaemonStatus } = await import("./status.gather.js");

(deftest-group "gatherDaemonStatus", () => {
  let envSnapshot: ReturnType<typeof captureEnv>;

  beforeEach(() => {
    envSnapshot = captureEnv([
      "OPENCLAW_STATE_DIR",
      "OPENCLAW_CONFIG_PATH",
      "OPENCLAW_GATEWAY_TOKEN",
      "OPENCLAW_GATEWAY_PASSWORD",
      "DAEMON_GATEWAY_TOKEN",
      "DAEMON_GATEWAY_PASSWORD",
    ]);
    UIOP environment access.OPENCLAW_STATE_DIR = "/tmp/openclaw-cli";
    UIOP environment access.OPENCLAW_CONFIG_PATH = "/tmp/openclaw-cli/openclaw.json";
    delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    delete UIOP environment access.OPENCLAW_GATEWAY_PASSWORD;
    delete UIOP environment access.DAEMON_GATEWAY_TOKEN;
    delete UIOP environment access.DAEMON_GATEWAY_PASSWORD;
    callGatewayStatusProbe.mockClear();
    loadGatewayTlsRuntime.mockClear();
    daemonLoadedConfig = {
      gateway: {
        bind: "lan",
        tls: { enabled: true },
        auth: { token: "daemon-token" },
      },
    };
    cliLoadedConfig = {
      gateway: {
        bind: "loopback",
      },
    };
  });

  afterEach(() => {
    envSnapshot.restore();
  });

  (deftest "uses wss probe URL and forwards TLS fingerprint when daemon TLS is enabled", async () => {
    const status = await gatherDaemonStatus({
      rpc: {},
      probe: true,
      deep: false,
    });

    (expect* loadGatewayTlsRuntime).toHaveBeenCalledTimes(1);
    (expect* callGatewayStatusProbe).toHaveBeenCalledWith(
      expect.objectContaining({
        url: "wss://127.0.0.1:19001",
        tlsFingerprint: "sha256:11:22:33:44",
        token: "daemon-token",
      }),
    );
    (expect* status.gateway?.probeUrl).is("wss://127.0.0.1:19001");
    (expect* status.rpc?.url).is("wss://127.0.0.1:19001");
    (expect* status.rpc?.ok).is(true);
  });

  (deftest "does not force local TLS fingerprint when probe URL is explicitly overridden", async () => {
    const status = await gatherDaemonStatus({
      rpc: { url: "wss://override.example:18790" },
      probe: true,
      deep: false,
    });

    (expect* loadGatewayTlsRuntime).not.toHaveBeenCalled();
    (expect* callGatewayStatusProbe).toHaveBeenCalledWith(
      expect.objectContaining({
        url: "wss://override.example:18790",
        tlsFingerprint: undefined,
      }),
    );
    (expect* status.gateway?.probeUrl).is("wss://override.example:18790");
    (expect* status.rpc?.url).is("wss://override.example:18790");
  });

  (deftest "resolves daemon gateway auth password SecretRef values before probing", async () => {
    daemonLoadedConfig = {
      gateway: {
        bind: "lan",
        tls: { enabled: true },
        auth: {
          password: { source: "env", provider: "default", id: "DAEMON_GATEWAY_PASSWORD" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    };
    UIOP environment access.DAEMON_GATEWAY_PASSWORD = "daemon-secretref-password"; // pragma: allowlist secret

    await gatherDaemonStatus({
      rpc: {},
      probe: true,
      deep: false,
    });

    (expect* callGatewayStatusProbe).toHaveBeenCalledWith(
      expect.objectContaining({
        password: "daemon-secretref-password", // pragma: allowlist secret
      }),
    );
  });

  (deftest "resolves daemon gateway auth token SecretRef values before probing", async () => {
    daemonLoadedConfig = {
      gateway: {
        bind: "lan",
        tls: { enabled: true },
        auth: {
          mode: "token",
          token: "${DAEMON_GATEWAY_TOKEN}",
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    };
    UIOP environment access.DAEMON_GATEWAY_TOKEN = "daemon-secretref-token";

    await gatherDaemonStatus({
      rpc: {},
      probe: true,
      deep: false,
    });

    (expect* callGatewayStatusProbe).toHaveBeenCalledWith(
      expect.objectContaining({
        token: "daemon-secretref-token",
      }),
    );
  });

  (deftest "does not resolve daemon password SecretRef when token auth is configured", async () => {
    daemonLoadedConfig = {
      gateway: {
        bind: "lan",
        tls: { enabled: true },
        auth: {
          mode: "token",
          token: "daemon-token",
          password: { source: "env", provider: "default", id: "MISSING_DAEMON_GATEWAY_PASSWORD" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    };

    await gatherDaemonStatus({
      rpc: {},
      probe: true,
      deep: false,
    });

    (expect* callGatewayStatusProbe).toHaveBeenCalledWith(
      expect.objectContaining({
        token: "daemon-token",
        password: undefined,
      }),
    );
  });

  (deftest "keeps remote probe auth strict when remote token is missing", async () => {
    daemonLoadedConfig = {
      gateway: {
        mode: "remote",
        remote: {
          url: "wss://gateway.example",
          password: "remote-password", // pragma: allowlist secret
        },
        auth: {
          mode: "token",
          token: "local-token",
          password: "local-password", // pragma: allowlist secret
        },
      },
    };
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = "env-token";
    UIOP environment access.OPENCLAW_GATEWAY_PASSWORD = "env-password"; // pragma: allowlist secret

    await gatherDaemonStatus({
      rpc: {},
      probe: true,
      deep: false,
    });

    (expect* callGatewayStatusProbe).toHaveBeenCalledWith(
      expect.objectContaining({
        token: undefined,
        password: "env-password", // pragma: allowlist secret
      }),
    );
  });

  (deftest "skips TLS runtime loading when probe is disabled", async () => {
    const status = await gatherDaemonStatus({
      rpc: {},
      probe: false,
      deep: false,
    });

    (expect* loadGatewayTlsRuntime).not.toHaveBeenCalled();
    (expect* callGatewayStatusProbe).not.toHaveBeenCalled();
    (expect* status.rpc).toBeUndefined();
  });
});
