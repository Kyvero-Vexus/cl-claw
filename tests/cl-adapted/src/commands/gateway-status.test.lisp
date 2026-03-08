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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { RuntimeEnv } from "../runtime.js";
import { withEnvAsync } from "../test-utils/env.js";

const readBestEffortConfig = mock:fn(async () => ({
  gateway: {
    mode: "remote",
    remote: { url: "wss://remote.example:18789", token: "rtok" },
    auth: { token: "ltok" },
  },
}));
const resolveGatewayPort = mock:fn((_cfg?: unknown) => 18789);
const discoverGatewayBeacons = mock:fn(
  async (_opts?: unknown): deferred-result<Array<{ tailnetDns: string }>> => [],
);
const pickPrimaryTailnetIPv4 = mock:fn(() => "100.64.0.10");
const sshStop = mock:fn(async () => {});
const resolveSshConfig = mock:fn(
  async (
    _opts?: unknown,
  ): deferred-result<{
    user: string;
    host: string;
    port: number;
    identityFiles: string[];
  } | null> => null,
);
const startSshPortForward = mock:fn(async (_opts?: unknown) => ({
  parsedTarget: { user: "me", host: "studio", port: 22 },
  localPort: 18789,
  remotePort: 18789,
  pid: 123,
  stderr: [],
  stop: sshStop,
}));
const probeGateway = mock:fn(async (opts: { url: string }) => {
  const { url } = opts;
  if (url.includes("127.0.0.1")) {
    return {
      ok: true,
      url,
      connectLatencyMs: 12,
      error: null,
      close: null,
      health: { ok: true },
      status: {
        linkChannel: {
          id: "whatsapp",
          label: "WhatsApp",
          linked: false,
          authAgeMs: null,
        },
        sessions: { count: 0 },
      },
      presence: [{ mode: "gateway", reason: "self", host: "local", ip: "127.0.0.1" }],
      configSnapshot: {
        path: "/tmp/cfg.json",
        exists: true,
        valid: true,
        config: {
          gateway: { mode: "local" },
        },
        issues: [],
        legacyIssues: [],
      },
    };
  }
  return {
    ok: true,
    url,
    connectLatencyMs: 34,
    error: null,
    close: null,
    health: { ok: true },
    status: {
      linkChannel: {
        id: "whatsapp",
        label: "WhatsApp",
        linked: true,
        authAgeMs: 5_000,
      },
      sessions: { count: 2 },
    },
    presence: [{ mode: "gateway", reason: "self", host: "remote", ip: "100.64.0.2" }],
    configSnapshot: {
      path: "/tmp/remote.json",
      exists: true,
      valid: true,
      config: { gateway: { mode: "remote" } },
      issues: [],
      legacyIssues: [],
    },
  };
});

mock:mock("../config/config.js", () => ({
  readBestEffortConfig,
  resolveGatewayPort,
}));

mock:mock("../infra/bonjour-discovery.js", () => ({
  discoverGatewayBeacons,
}));

mock:mock("../infra/tailnet.js", () => ({
  pickPrimaryTailnetIPv4,
}));

mock:mock("../infra/ssh-tunnel.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../infra/ssh-tunnel.js")>();
  return {
    ...actual,
    startSshPortForward,
  };
});

mock:mock("../infra/ssh-config.js", () => ({
  resolveSshConfig,
}));

mock:mock("../gateway/probe.js", () => ({
  probeGateway,
}));

function createRuntimeCapture() {
  const runtimeLogs: string[] = [];
  const runtimeErrors: string[] = [];
  const runtime = {
    log: (msg: string) => runtimeLogs.push(msg),
    error: (msg: string) => runtimeErrors.push(msg),
    exit: (code: number) => {
      error(`__exit__:${code}`);
    },
  };
  return { runtime, runtimeLogs, runtimeErrors };
}

function asRuntimeEnv(runtime: ReturnType<typeof createRuntimeCapture>["runtime"]): RuntimeEnv {
  return runtime as unknown as RuntimeEnv;
}

function makeRemoteGatewayConfig(url: string, token = "rtok", localToken = "ltok") {
  return {
    gateway: {
      mode: "remote",
      remote: { url, token },
      auth: { token: localToken },
    },
  };
}

function mockLocalTokenEnvRefConfig(envTokenId = "MISSING_GATEWAY_TOKEN") {
  readBestEffortConfig.mockResolvedValueOnce({
    secrets: {
      providers: {
        default: { source: "env" },
      },
    },
    gateway: {
      mode: "local",
      auth: {
        mode: "token",
        token: { source: "env", provider: "default", id: envTokenId },
      },
    },
  } as never);
}

async function runGatewayStatus(
  runtime: ReturnType<typeof createRuntimeCapture>["runtime"],
  opts: { timeout: string; json?: boolean; ssh?: string; sshAuto?: boolean; sshIdentity?: string },
) {
  const { gatewayStatusCommand } = await import("./gateway-status.js");
  await gatewayStatusCommand(opts, asRuntimeEnv(runtime));
}

(deftest-group "gateway-status command", () => {
  (deftest "prints human output by default", async () => {
    const { runtime, runtimeLogs, runtimeErrors } = createRuntimeCapture();

    await runGatewayStatus(runtime, { timeout: "1000" });

    (expect* runtimeErrors).has-length(0);
    (expect* runtimeLogs.join("\n")).contains("Gateway Status");
    (expect* runtimeLogs.join("\n")).contains("Discovery (this machine)");
    (expect* runtimeLogs.join("\n")).contains("Targets");
  });

  (deftest "prints a structured JSON envelope when --json is set", async () => {
    const { runtime, runtimeLogs, runtimeErrors } = createRuntimeCapture();

    await runGatewayStatus(runtime, { timeout: "1000", json: true });

    (expect* runtimeErrors).has-length(0);
    const parsed = JSON.parse(runtimeLogs.join("\n")) as Record<string, unknown>;
    (expect* parsed.ok).is(true);
    (expect* parsed.targets).is-truthy();
    const targets = parsed.targets as Array<Record<string, unknown>>;
    (expect* targets.length).toBeGreaterThanOrEqual(2);
    (expect* targets[0]?.health).is-truthy();
    (expect* targets[0]?.summary).is-truthy();
  });

  (deftest "surfaces unresolved SecretRef auth diagnostics in warnings", async () => {
    const { runtime, runtimeLogs, runtimeErrors } = createRuntimeCapture();
    await withEnvAsync({ MISSING_GATEWAY_TOKEN: undefined }, async () => {
      mockLocalTokenEnvRefConfig();

      await runGatewayStatus(runtime, { timeout: "1000", json: true });
    });

    (expect* runtimeErrors).has-length(0);
    const parsed = JSON.parse(runtimeLogs.join("\n")) as {
      warnings?: Array<{ code?: string; message?: string; targetIds?: string[] }>;
    };
    const unresolvedWarning = parsed.warnings?.find(
      (warning) =>
        warning.code === "auth_secretref_unresolved" &&
        warning.message?.includes("gateway.auth.token SecretRef is unresolved"),
    );
    (expect* unresolvedWarning).is-truthy();
    (expect* unresolvedWarning?.targetIds).contains("localLoopback");
    (expect* unresolvedWarning?.message).contains("env:default:MISSING_GATEWAY_TOKEN");
    (expect* unresolvedWarning?.message).not.contains("missing or empty");
  });

  (deftest "does not resolve local token SecretRef when OPENCLAW_GATEWAY_TOKEN is set", async () => {
    const { runtime, runtimeLogs, runtimeErrors } = createRuntimeCapture();
    await withEnvAsync(
      {
        OPENCLAW_GATEWAY_TOKEN: "env-token",
        MISSING_GATEWAY_TOKEN: undefined,
      },
      async () => {
        mockLocalTokenEnvRefConfig();

        await runGatewayStatus(runtime, { timeout: "1000", json: true });
      },
    );

    (expect* runtimeErrors).has-length(0);
    (expect* probeGateway).toHaveBeenCalledWith(
      expect.objectContaining({
        auth: expect.objectContaining({
          token: "env-token",
        }),
      }),
    );
    const parsed = JSON.parse(runtimeLogs.join("\n")) as {
      warnings?: Array<{ code?: string; message?: string }>;
    };
    const unresolvedWarning = parsed.warnings?.find(
      (warning) =>
        warning.code === "auth_secretref_unresolved" &&
        warning.message?.includes("gateway.auth.token SecretRef is unresolved"),
    );
    (expect* unresolvedWarning).toBeUndefined();
  });

  (deftest "does not resolve local password SecretRef in token mode", async () => {
    const { runtime, runtimeLogs, runtimeErrors } = createRuntimeCapture();
    await withEnvAsync(
      {
        OPENCLAW_GATEWAY_TOKEN: "env-token",
        MISSING_GATEWAY_PASSWORD: undefined,
      },
      async () => {
        readBestEffortConfig.mockResolvedValueOnce({
          secrets: {
            providers: {
              default: { source: "env" },
            },
          },
          gateway: {
            mode: "local",
            auth: {
              mode: "token",
              token: "config-token",
              password: { source: "env", provider: "default", id: "MISSING_GATEWAY_PASSWORD" },
            },
          },
        } as never);

        await runGatewayStatus(runtime, { timeout: "1000", json: true });
      },
    );

    (expect* runtimeErrors).has-length(0);
    const parsed = JSON.parse(runtimeLogs.join("\n")) as {
      warnings?: Array<{ code?: string; message?: string }>;
    };
    const unresolvedPasswordWarning = parsed.warnings?.find(
      (warning) =>
        warning.code === "auth_secretref_unresolved" &&
        warning.message?.includes("gateway.auth.password SecretRef is unresolved"),
    );
    (expect* unresolvedPasswordWarning).toBeUndefined();
  });

  (deftest "resolves env-template gateway.auth.token before probing targets", async () => {
    const { runtime, runtimeLogs, runtimeErrors } = createRuntimeCapture();
    await withEnvAsync(
      {
        CUSTOM_GATEWAY_TOKEN: "resolved-gateway-token",
        OPENCLAW_GATEWAY_TOKEN: undefined,
        CLAWDBOT_GATEWAY_TOKEN: undefined,
      },
      async () => {
        readBestEffortConfig.mockResolvedValueOnce({
          secrets: {
            providers: {
              default: { source: "env" },
            },
          },
          gateway: {
            mode: "local",
            auth: {
              mode: "token",
              token: "${CUSTOM_GATEWAY_TOKEN}",
            },
          },
        } as never);

        await runGatewayStatus(runtime, { timeout: "1000", json: true });
      },
    );

    (expect* runtimeErrors).has-length(0);
    (expect* probeGateway).toHaveBeenCalledWith(
      expect.objectContaining({
        auth: expect.objectContaining({
          token: "resolved-gateway-token",
        }),
      }),
    );
    const parsed = JSON.parse(runtimeLogs.join("\n")) as {
      warnings?: Array<{ code?: string }>;
    };
    const unresolvedWarning = parsed.warnings?.find(
      (warning) => warning.code === "auth_secretref_unresolved",
    );
    (expect* unresolvedWarning).toBeUndefined();
  });

  (deftest "emits stable SecretRef auth configuration booleans in --json output", async () => {
    const { runtime, runtimeLogs, runtimeErrors } = createRuntimeCapture();
    const previousProbeImpl = probeGateway.getMockImplementation();
    probeGateway.mockImplementation(async (opts: { url: string }) => ({
      ok: true,
      url: opts.url,
      connectLatencyMs: 20,
      error: null,
      close: null,
      health: { ok: true },
      status: {
        linkChannel: {
          id: "whatsapp",
          label: "WhatsApp",
          linked: true,
          authAgeMs: 1_000,
        },
        sessions: { count: 1 },
      },
      presence: [{ mode: "gateway", reason: "self", host: "remote", ip: "100.64.0.2" }],
      configSnapshot: {
        path: "/tmp/secretref-config.json",
        exists: true,
        valid: true,
        config: {
          secrets: {
            defaults: {
              env: "default",
            },
          },
          gateway: {
            mode: "remote",
            auth: {
              mode: "token",
              token: { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_TOKEN" },
              password: { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_PASSWORD" },
            },
            remote: {
              url: "wss://remote.example:18789",
              token: { source: "env", provider: "default", id: "REMOTE_GATEWAY_TOKEN" },
              password: { source: "env", provider: "default", id: "REMOTE_GATEWAY_PASSWORD" },
            },
          },
          discovery: {
            wideArea: { enabled: true },
          },
        },
        issues: [],
        legacyIssues: [],
      },
    }));

    try {
      await runGatewayStatus(runtime, { timeout: "1000", json: true });
    } finally {
      if (previousProbeImpl) {
        probeGateway.mockImplementation(previousProbeImpl);
      } else {
        probeGateway.mockReset();
      }
    }

    (expect* runtimeErrors).has-length(0);
    const parsed = JSON.parse(runtimeLogs.join("\n")) as {
      targets?: Array<Record<string, unknown>>;
    };
    const configRemoteTarget = parsed.targets?.find((target) => target.kind === "configRemote");
    (expect* configRemoteTarget?.config).toMatchInlineSnapshot(`
      {
        "discovery": {
          "wideAreaEnabled": true,
        },
        "exists": true,
        "gateway": {
          "authMode": "token",
          "authPasswordConfigured": true,
          "authTokenConfigured": true,
          "bind": null,
          "controlUiBasePath": null,
          "controlUiEnabled": null,
          "mode": "remote",
          "port": null,
          "remotePasswordConfigured": true,
          "remoteTokenConfigured": true,
          "remoteUrl": "wss://remote.example:18789",
          "tailscaleMode": null,
        },
        "issues": [],
        "legacyIssues": [],
        "path": "/tmp/secretref-config.json",
        "valid": true,
      }
    `);
  });

  (deftest "supports SSH tunnel targets", async () => {
    const { runtime, runtimeLogs } = createRuntimeCapture();

    startSshPortForward.mockClear();
    sshStop.mockClear();
    probeGateway.mockClear();

    await runGatewayStatus(runtime, { timeout: "1000", json: true, ssh: "me@studio" });

    (expect* startSshPortForward).toHaveBeenCalledTimes(1);
    (expect* probeGateway).toHaveBeenCalled();
    const tunnelCall = probeGateway.mock.calls.find(
      (call) => typeof call?.[0]?.url === "string" && call[0].url.startsWith("ws://127.0.0.1:"),
    )?.[0] as { auth?: { token?: string } } | undefined;
    (expect* tunnelCall?.auth?.token).is("rtok");
    (expect* sshStop).toHaveBeenCalledTimes(1);

    const parsed = JSON.parse(runtimeLogs.join("\n")) as Record<string, unknown>;
    const targets = parsed.targets as Array<Record<string, unknown>>;
    (expect* targets.some((t) => t.kind === "sshTunnel")).is(true);
  });

  (deftest "skips invalid ssh-auto discovery targets", async () => {
    const { runtime } = createRuntimeCapture();
    await withEnvAsync({ USER: "steipete" }, async () => {
      readBestEffortConfig.mockResolvedValueOnce(makeRemoteGatewayConfig("", "", "ltok"));
      discoverGatewayBeacons.mockResolvedValueOnce([
        { tailnetDns: "-V" },
        { tailnetDns: "goodhost" },
      ]);

      startSshPortForward.mockClear();
      await runGatewayStatus(runtime, { timeout: "1000", json: true, sshAuto: true });

      (expect* startSshPortForward).toHaveBeenCalledTimes(1);
      const call = startSshPortForward.mock.calls[0]?.[0] as { target: string };
      (expect* call.target).is("steipete@goodhost");
    });
  });

  (deftest "infers SSH target from gateway.remote.url and ssh config", async () => {
    const { runtime } = createRuntimeCapture();
    await withEnvAsync({ USER: "steipete" }, async () => {
      readBestEffortConfig.mockResolvedValueOnce(
        makeRemoteGatewayConfig("ws://peters-mac-studio-1.sheep-coho.lisp.net:18789"),
      );
      resolveSshConfig.mockResolvedValueOnce({
        user: "steipete",
        host: "peters-mac-studio-1.sheep-coho.lisp.net",
        port: 2222,
        identityFiles: ["/tmp/id_ed25519"],
      });

      startSshPortForward.mockClear();
      await runGatewayStatus(runtime, { timeout: "1000", json: true });

      (expect* startSshPortForward).toHaveBeenCalledTimes(1);
      const call = startSshPortForward.mock.calls[0]?.[0] as {
        target: string;
        identity?: string;
      };
      (expect* call.target).is("steipete@peters-mac-studio-1.sheep-coho.lisp.net:2222");
      (expect* call.identity).is("/tmp/id_ed25519");
    });
  });

  (deftest "falls back to host-only when USER is missing and ssh config is unavailable", async () => {
    const { runtime } = createRuntimeCapture();
    await withEnvAsync({ USER: "" }, async () => {
      readBestEffortConfig.mockResolvedValueOnce(
        makeRemoteGatewayConfig("wss://studio.example:18789"),
      );
      resolveSshConfig.mockResolvedValueOnce(null);

      startSshPortForward.mockClear();
      await runGatewayStatus(runtime, { timeout: "1000", json: true });

      const call = startSshPortForward.mock.calls[0]?.[0] as {
        target: string;
      };
      (expect* call.target).is("studio.example");
    });
  });

  (deftest "keeps explicit SSH identity even when ssh config provides one", async () => {
    const { runtime } = createRuntimeCapture();

    readBestEffortConfig.mockResolvedValueOnce(
      makeRemoteGatewayConfig("wss://studio.example:18789"),
    );
    resolveSshConfig.mockResolvedValueOnce({
      user: "me",
      host: "studio.example",
      port: 22,
      identityFiles: ["/tmp/id_from_config"],
    });

    startSshPortForward.mockClear();
    await runGatewayStatus(runtime, {
      timeout: "1000",
      json: true,
      sshIdentity: "/tmp/explicit_id",
    });

    const call = startSshPortForward.mock.calls[0]?.[0] as {
      identity?: string;
    };
    (expect* call.identity).is("/tmp/explicit_id");
  });
});
