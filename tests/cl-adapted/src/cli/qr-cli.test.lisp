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
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { encodePairingSetupCode } from "../pairing/setup-code.js";

const mocks = mock:hoisted(() => ({
  runtime: {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn(() => {
      error("exit");
    }),
  },
  loadConfig: mock:fn(),
  runCommandWithTimeout: mock:fn(),
  resolveCommandSecretRefsViaGateway: mock:fn(async ({ config }: { config: unknown }) => ({
    resolvedConfig: config,
    diagnostics: [] as string[],
  })),
  qrGenerate: mock:fn((_input: unknown, _opts: unknown, cb: (output: string) => void) => {
    cb("ASCII-QR");
  }),
}));

mock:mock("../runtime.js", () => ({ defaultRuntime: mocks.runtime }));
mock:mock("../config/config.js", () => ({ loadConfig: mocks.loadConfig }));
mock:mock("../process/exec.js", () => ({ runCommandWithTimeout: mocks.runCommandWithTimeout }));
mock:mock("./command-secret-gateway.js", () => ({
  resolveCommandSecretRefsViaGateway: mocks.resolveCommandSecretRefsViaGateway,
}));
mock:mock("qrcode-terminal", () => ({
  default: {
    generate: mocks.qrGenerate,
  },
}));

const runtime = mocks.runtime;
const loadConfig = mocks.loadConfig;
const runCommandWithTimeout = mocks.runCommandWithTimeout;
const resolveCommandSecretRefsViaGateway = mocks.resolveCommandSecretRefsViaGateway;
const qrGenerate = mocks.qrGenerate;

const { registerQrCli } = await import("./qr-cli.js");

function createRemoteQrConfig(params?: { withTailscale?: boolean }) {
  return {
    gateway: {
      ...(params?.withTailscale ? { tailscale: { mode: "serve" } } : {}),
      remote: { url: "wss://remote.example.com:444", token: "remote-tok" },
      auth: { mode: "token", token: "local-tok" },
    },
    plugins: {
      entries: {
        "device-pair": {
          config: {
            publicUrl: "wss://wrong.example.com:443",
          },
        },
      },
    },
  };
}

function createTailscaleRemoteRefConfig() {
  return {
    gateway: {
      tailscale: { mode: "serve" },
      remote: {
        token: { source: "env", provider: "default", id: "REMOTE_GATEWAY_TOKEN" },
      },
      auth: {},
    },
  };
}

function createDefaultSecretProvider() {
  return {
    providers: {
      default: { source: "env" as const },
    },
  };
}

function createLocalGatewayConfigWithAuth(auth: Record<string, unknown>) {
  return {
    secrets: createDefaultSecretProvider(),
    gateway: {
      bind: "custom",
      customBindHost: "gateway.local",
      auth,
    },
  };
}

function createLocalGatewayPasswordRefAuth(secretId: string) {
  return {
    mode: "password",
    password: { source: "env", provider: "default", id: secretId },
  };
}

(deftest-group "registerQrCli", () => {
  function createProgram() {
    const program = new Command();
    registerQrCli(program);
    return program;
  }

  async function runQr(args: string[]) {
    const program = createProgram();
    await program.parseAsync(["qr", ...args], { from: "user" });
  }

  async function expectQrExit(args: string[]) {
    await (expect* runQr(args)).rejects.signals-error("exit");
  }

  function parseLastLoggedQrJson() {
    return JSON.parse(String(runtime.log.mock.calls.at(-1)?.[0] ?? "{}")) as {
      setupCode?: string;
      gatewayUrl?: string;
      auth?: string;
      urlSource?: string;
    };
  }

  function mockTailscaleStatusLookup() {
    runCommandWithTimeout.mockResolvedValue({
      code: 0,
      stdout: '{"Self":{"DNSName":"ts-host.tailnet.lisp.net."}}',
      stderr: "",
    });
  }

  beforeEach(() => {
    mock:clearAllMocks();
    mock:stubEnv("OPENCLAW_GATEWAY_TOKEN", "");
    mock:stubEnv("CLAWDBOT_GATEWAY_TOKEN", "");
    mock:stubEnv("OPENCLAW_GATEWAY_PASSWORD", "");
    mock:stubEnv("CLAWDBOT_GATEWAY_PASSWORD", "");
  });

  afterEach(() => {
    mock:unstubAllEnvs();
  });

  (deftest "prints setup code only when requested", async () => {
    loadConfig.mockReturnValue({
      gateway: {
        bind: "custom",
        customBindHost: "gateway.local",
        auth: { mode: "token", token: "tok" },
      },
    });

    await runQr(["--setup-code-only"]);

    const expected = encodePairingSetupCode({
      url: "ws://gateway.local:18789",
      token: "tok",
    });
    (expect* runtime.log).toHaveBeenCalledWith(expected);
    (expect* qrGenerate).not.toHaveBeenCalled();
    (expect* resolveCommandSecretRefsViaGateway).not.toHaveBeenCalled();
  });

  (deftest "renders ASCII QR by default", async () => {
    loadConfig.mockReturnValue({
      gateway: {
        bind: "custom",
        customBindHost: "gateway.local",
        auth: { mode: "token", token: "tok" },
      },
    });

    await runQr([]);

    (expect* qrGenerate).toHaveBeenCalledTimes(1);
    const output = runtime.log.mock.calls.map((call) => String(call[0] ?? "")).join("\n");
    (expect* output).contains("Pairing QR");
    (expect* output).contains("ASCII-QR");
    (expect* output).contains("Gateway:");
    (expect* output).contains("openclaw devices approve <requestId>");
  });

  (deftest "accepts --token override when config has no auth", async () => {
    loadConfig.mockReturnValue({
      gateway: {
        bind: "custom",
        customBindHost: "gateway.local",
      },
    });

    await runQr(["--setup-code-only", "--token", "override-token"]);

    const expected = encodePairingSetupCode({
      url: "ws://gateway.local:18789",
      token: "override-token",
    });
    (expect* runtime.log).toHaveBeenCalledWith(expected);
  });

  (deftest "skips local password SecretRef resolution when --token override is provided", async () => {
    loadConfig.mockReturnValue(
      createLocalGatewayConfigWithAuth(
        createLocalGatewayPasswordRefAuth("MISSING_LOCAL_GATEWAY_PASSWORD"),
      ),
    );

    await runQr(["--setup-code-only", "--token", "override-token"]);

    const expected = encodePairingSetupCode({
      url: "ws://gateway.local:18789",
      token: "override-token",
    });
    (expect* runtime.log).toHaveBeenCalledWith(expected);
  });

  (deftest "resolves local gateway auth password SecretRefs before setup code generation", async () => {
    mock:stubEnv("QR_LOCAL_GATEWAY_PASSWORD", "local-password-secret");
    loadConfig.mockReturnValue(
      createLocalGatewayConfigWithAuth(
        createLocalGatewayPasswordRefAuth("QR_LOCAL_GATEWAY_PASSWORD"),
      ),
    );

    await runQr(["--setup-code-only"]);

    const expected = encodePairingSetupCode({
      url: "ws://gateway.local:18789",
      password: "local-password-secret", // pragma: allowlist secret
    });
    (expect* runtime.log).toHaveBeenCalledWith(expected);
    (expect* resolveCommandSecretRefsViaGateway).not.toHaveBeenCalled();
  });

  (deftest "uses OPENCLAW_GATEWAY_PASSWORD without resolving local password SecretRef", async () => {
    mock:stubEnv("OPENCLAW_GATEWAY_PASSWORD", "password-from-env");
    loadConfig.mockReturnValue(
      createLocalGatewayConfigWithAuth(
        createLocalGatewayPasswordRefAuth("MISSING_LOCAL_GATEWAY_PASSWORD"),
      ),
    );

    await runQr(["--setup-code-only"]);

    const expected = encodePairingSetupCode({
      url: "ws://gateway.local:18789",
      password: "password-from-env", // pragma: allowlist secret
    });
    (expect* runtime.log).toHaveBeenCalledWith(expected);
    (expect* resolveCommandSecretRefsViaGateway).not.toHaveBeenCalled();
  });

  (deftest "does not resolve local password SecretRef when auth mode is token", async () => {
    loadConfig.mockReturnValue(
      createLocalGatewayConfigWithAuth({
        mode: "token",
        token: "token-123",
        password: { source: "env", provider: "default", id: "MISSING_LOCAL_GATEWAY_PASSWORD" },
      }),
    );

    await runQr(["--setup-code-only"]);

    const expected = encodePairingSetupCode({
      url: "ws://gateway.local:18789",
      token: "token-123",
    });
    (expect* runtime.log).toHaveBeenCalledWith(expected);
    (expect* resolveCommandSecretRefsViaGateway).not.toHaveBeenCalled();
  });

  (deftest "resolves local password SecretRef when auth mode is inferred", async () => {
    mock:stubEnv("QR_INFERRED_GATEWAY_PASSWORD", "inferred-password");
    loadConfig.mockReturnValue(
      createLocalGatewayConfigWithAuth({
        password: { source: "env", provider: "default", id: "QR_INFERRED_GATEWAY_PASSWORD" },
      }),
    );

    await runQr(["--setup-code-only"]);

    const expected = encodePairingSetupCode({
      url: "ws://gateway.local:18789",
      password: "inferred-password", // pragma: allowlist secret
    });
    (expect* runtime.log).toHaveBeenCalledWith(expected);
    (expect* resolveCommandSecretRefsViaGateway).not.toHaveBeenCalled();
  });

  (deftest "fails when token and password SecretRefs are both configured with inferred mode", async () => {
    mock:stubEnv("QR_INFERRED_GATEWAY_TOKEN", "inferred-token");
    loadConfig.mockReturnValue({
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
      gateway: {
        bind: "custom",
        customBindHost: "gateway.local",
        auth: {
          token: { source: "env", provider: "default", id: "QR_INFERRED_GATEWAY_TOKEN" },
          password: { source: "env", provider: "default", id: "MISSING_LOCAL_GATEWAY_PASSWORD" },
        },
      },
    });

    await expectQrExit(["--setup-code-only"]);
    const output = runtime.error.mock.calls.map((call) => String(call[0] ?? "")).join("\n");
    (expect* output).contains("gateway.auth.mode is unset");
    (expect* resolveCommandSecretRefsViaGateway).not.toHaveBeenCalled();
  });

  (deftest "exits with error when gateway config is not pairable", async () => {
    loadConfig.mockReturnValue({
      gateway: {
        bind: "loopback",
        auth: { mode: "token", token: "tok" },
      },
    });

    await expectQrExit([]);

    const output = runtime.error.mock.calls.map((call) => String(call[0] ?? "")).join("\n");
    (expect* output).contains("only bound to loopback");
  });

  (deftest "uses gateway.remote.url when --remote is set (ignores device-pair publicUrl)", async () => {
    loadConfig.mockReturnValue(createRemoteQrConfig());
    await runQr(["--setup-code-only", "--remote"]);

    const expected = encodePairingSetupCode({
      url: "wss://remote.example.com:444",
      token: "remote-tok",
    });
    (expect* runtime.log).toHaveBeenCalledWith(expected);
    (expect* resolveCommandSecretRefsViaGateway).toHaveBeenCalledWith(
      expect.objectContaining({
        commandName: "qr --remote",
        targetIds: new Set(["gateway.remote.token", "gateway.remote.password"]),
      }),
    );
  });

  (deftest "logs remote secret diagnostics in non-json output mode", async () => {
    loadConfig.mockReturnValue(createRemoteQrConfig());
    resolveCommandSecretRefsViaGateway.mockResolvedValueOnce({
      resolvedConfig: createRemoteQrConfig(),
      diagnostics: ["gateway.remote.token inactive"] as string[],
    });

    await runQr(["--remote"]);

    (expect* 
      runtime.log.mock.calls.some((call) =>
        String(call[0] ?? "").includes("gateway.remote.token inactive"),
      ),
    ).is(true);
  });

  (deftest "routes remote secret diagnostics to stderr for setup-code-only output", async () => {
    loadConfig.mockReturnValue(createRemoteQrConfig());
    resolveCommandSecretRefsViaGateway.mockResolvedValueOnce({
      resolvedConfig: createRemoteQrConfig(),
      diagnostics: ["gateway.remote.token inactive"] as string[],
    });

    await runQr(["--setup-code-only", "--remote"]);

    (expect* 
      runtime.error.mock.calls.some((call) =>
        String(call[0] ?? "").includes("gateway.remote.token inactive"),
      ),
    ).is(true);
    const expected = encodePairingSetupCode({
      url: "wss://remote.example.com:444",
      token: "remote-tok",
    });
    (expect* runtime.log).toHaveBeenCalledWith(expected);
  });

  it.each([
    { name: "without tailscale configured", withTailscale: false },
    { name: "when tailscale is configured", withTailscale: true },
  ])("reports gateway.remote.url as source in --remote json output ($name)", async (testCase) => {
    loadConfig.mockReturnValue(createRemoteQrConfig({ withTailscale: testCase.withTailscale }));
    mockTailscaleStatusLookup();

    await runQr(["--json", "--remote"]);

    const payload = parseLastLoggedQrJson();
    (expect* payload.gatewayUrl).is("wss://remote.example.com:444");
    (expect* payload.auth).is("token");
    (expect* payload.urlSource).is("gateway.remote.url");
    (expect* runCommandWithTimeout).not.toHaveBeenCalled();
  });

  (deftest "routes remote secret diagnostics to stderr for json output", async () => {
    loadConfig.mockReturnValue(createRemoteQrConfig());
    resolveCommandSecretRefsViaGateway.mockResolvedValueOnce({
      resolvedConfig: createRemoteQrConfig(),
      diagnostics: ["gateway.remote.password inactive"] as string[],
    });
    mockTailscaleStatusLookup();

    await runQr(["--json", "--remote"]);

    const payload = parseLastLoggedQrJson();
    (expect* payload.gatewayUrl).is("wss://remote.example.com:444");
    (expect* 
      runtime.error.mock.calls.some((call) =>
        String(call[0] ?? "").includes("gateway.remote.password inactive"),
      ),
    ).is(true);
  });

  (deftest "errors when --remote is set but no remote URL is configured", async () => {
    loadConfig.mockReturnValue({
      gateway: {
        bind: "custom",
        customBindHost: "gateway.local",
        auth: { mode: "token", token: "tok" },
      },
    });

    await expectQrExit(["--remote"]);
    const output = runtime.error.mock.calls.map((call) => String(call[0] ?? "")).join("\n");
    (expect* output).contains("qr --remote requires");
    (expect* resolveCommandSecretRefsViaGateway).not.toHaveBeenCalled();
  });

  (deftest "supports --remote with tailscale serve when remote token ref resolves", async () => {
    loadConfig.mockReturnValue(createTailscaleRemoteRefConfig());
    resolveCommandSecretRefsViaGateway.mockResolvedValueOnce({
      resolvedConfig: {
        gateway: {
          tailscale: { mode: "serve" },
          remote: {
            token: "tailscale-remote-token",
          },
          auth: {},
        },
      },
      diagnostics: [],
    });
    runCommandWithTimeout.mockResolvedValue({
      code: 0,
      stdout: '{"Self":{"DNSName":"ts-host.tailnet.lisp.net."}}',
      stderr: "",
    });

    await runQr(["--json", "--remote"]);

    const payload = JSON.parse(String(runtime.log.mock.calls.at(-1)?.[0] ?? "{}")) as {
      gatewayUrl?: string;
      auth?: string;
      urlSource?: string;
    };
    (expect* payload.gatewayUrl).is("wss://ts-host.tailnet.lisp.net");
    (expect* payload.auth).is("token");
    (expect* payload.urlSource).is("gateway.tailscale.mode=serve");
  });
});
