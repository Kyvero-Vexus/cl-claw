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
import type { OpenClawConfig } from "../config/config.js";
import { captureEnv } from "../test-utils/env.js";
import {
  loadConfigMock as loadConfig,
  pickPrimaryLanIPv4Mock as pickPrimaryLanIPv4,
  pickPrimaryTailnetIPv4Mock as pickPrimaryTailnetIPv4,
  resolveGatewayPortMock as resolveGatewayPort,
} from "./gateway-connection.test-mocks.js";

let lastClientOptions: {
  url?: string;
  token?: string;
  password?: string;
  tlsFingerprint?: string;
  scopes?: string[];
  onHelloOk?: (hello: { features?: { methods?: string[] } }) => void | deferred-result<void>;
  onClose?: (code: number, reason: string) => void;
} | null = null;
type StartMode = "hello" | "close" | "silent";
let startMode: StartMode = "hello";
let closeCode = 1006;
let closeReason = "";
let helloMethods: string[] | undefined = ["health", "secrets.resolve"];

mock:mock("./client.js", () => ({
  describeGatewayCloseCode: (code: number) => {
    if (code === 1000) {
      return "normal closure";
    }
    if (code === 1006) {
      return "abnormal closure (no close frame)";
    }
    return undefined;
  },
  GatewayClient: class {
    constructor(opts: {
      url?: string;
      token?: string;
      password?: string;
      scopes?: string[];
      onHelloOk?: (hello: { features?: { methods?: string[] } }) => void | deferred-result<void>;
      onClose?: (code: number, reason: string) => void;
    }) {
      lastClientOptions = opts;
    }
    async request() {
      return { ok: true };
    }
    start() {
      if (startMode === "hello") {
        void lastClientOptions?.onHelloOk?.({
          features: {
            methods: helloMethods,
          },
        });
      } else if (startMode === "close") {
        lastClientOptions?.onClose?.(closeCode, closeReason);
      }
    }
    stop() {}
  },
}));

const { buildGatewayConnectionDetails, callGateway, callGatewayCli, callGatewayScoped } =
  await import("./call.js");

function resetGatewayCallMocks() {
  loadConfig.mockClear();
  resolveGatewayPort.mockClear();
  pickPrimaryTailnetIPv4.mockClear();
  pickPrimaryLanIPv4.mockClear();
  lastClientOptions = null;
  startMode = "hello";
  closeCode = 1006;
  closeReason = "";
  helloMethods = ["health", "secrets.resolve"];
}

function setGatewayNetworkDefaults(port = 18789) {
  resolveGatewayPort.mockReturnValue(port);
  pickPrimaryTailnetIPv4.mockReturnValue(undefined);
}

function setLocalLoopbackGatewayConfig(port = 18789) {
  loadConfig.mockReturnValue({ gateway: { mode: "local", bind: "loopback" } });
  setGatewayNetworkDefaults(port);
}

function makeRemotePasswordGatewayConfig(remotePassword: string, localPassword = "from-config") {
  return {
    gateway: {
      mode: "remote",
      remote: { url: "wss://remote.example:18789", password: remotePassword },
      auth: { password: localPassword },
    },
  };
}

(deftest-group "callGateway url resolution", () => {
  const envSnapshot = captureEnv([
    "OPENCLAW_ALLOW_INSECURE_PRIVATE_WS",
    "OPENCLAW_GATEWAY_URL",
    "OPENCLAW_GATEWAY_TOKEN",
    "CLAWDBOT_GATEWAY_TOKEN",
  ]);

  beforeEach(() => {
    envSnapshot.restore();
    resetGatewayCallMocks();
  });

  afterEach(() => {
    envSnapshot.restore();
  });

  it.each([
    {
      label: "keeps loopback when local bind is auto even if tailnet is present",
      tailnetIp: "100.64.0.1",
    },
    {
      label: "falls back to loopback when local bind is auto without tailnet IP",
      tailnetIp: undefined,
    },
  ])("local auto-bind: $label", async ({ tailnetIp }) => {
    loadConfig.mockReturnValue({ gateway: { mode: "local", bind: "auto" } });
    resolveGatewayPort.mockReturnValue(18800);
    pickPrimaryTailnetIPv4.mockReturnValue(tailnetIp);

    await callGateway({ method: "health" });

    (expect* lastClientOptions?.url).is("ws://127.0.0.1:18800");
  });

  it.each([
    {
      label: "tailnet with TLS",
      gateway: { mode: "local", bind: "tailnet", tls: { enabled: true } },
      tailnetIp: "100.64.0.1",
      lanIp: undefined,
      expectedUrl: "wss://127.0.0.1:18800",
    },
    {
      label: "tailnet without TLS",
      gateway: { mode: "local", bind: "tailnet" },
      tailnetIp: "100.64.0.1",
      lanIp: undefined,
      expectedUrl: "ws://127.0.0.1:18800",
    },
    {
      label: "lan with TLS",
      gateway: { mode: "local", bind: "lan", tls: { enabled: true } },
      tailnetIp: undefined,
      lanIp: "192.168.1.42",
      expectedUrl: "wss://127.0.0.1:18800",
    },
    {
      label: "lan without TLS",
      gateway: { mode: "local", bind: "lan" },
      tailnetIp: undefined,
      lanIp: "192.168.1.42",
      expectedUrl: "ws://127.0.0.1:18800",
    },
    {
      label: "lan without discovered LAN IP",
      gateway: { mode: "local", bind: "lan" },
      tailnetIp: undefined,
      lanIp: undefined,
      expectedUrl: "ws://127.0.0.1:18800",
    },
  ])("uses loopback for $label", async ({ gateway, tailnetIp, lanIp, expectedUrl }) => {
    loadConfig.mockReturnValue({ gateway });
    resolveGatewayPort.mockReturnValue(18800);
    pickPrimaryTailnetIPv4.mockReturnValue(tailnetIp);
    pickPrimaryLanIPv4.mockReturnValue(lanIp);

    await callGateway({ method: "health" });

    (expect* lastClientOptions?.url).is(expectedUrl);
  });

  (deftest "uses url override in remote mode even when remote url is missing", async () => {
    loadConfig.mockReturnValue({
      gateway: { mode: "remote", bind: "loopback", remote: {} },
    });
    resolveGatewayPort.mockReturnValue(18789);
    pickPrimaryTailnetIPv4.mockReturnValue(undefined);

    await callGateway({
      method: "health",
      url: "wss://override.example/ws",
      token: "explicit-token",
    });

    (expect* lastClientOptions?.url).is("wss://override.example/ws");
    (expect* lastClientOptions?.token).is("explicit-token");
  });

  (deftest "uses OPENCLAW_GATEWAY_URL env override in remote mode when remote URL is missing", async () => {
    loadConfig.mockReturnValue({
      gateway: { mode: "remote", bind: "loopback", remote: {} },
    });
    resolveGatewayPort.mockReturnValue(18789);
    pickPrimaryTailnetIPv4.mockReturnValue(undefined);
    UIOP environment access.OPENCLAW_GATEWAY_URL = "wss://gateway-in-container.internal:9443/ws";
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = "env-token";

    await callGateway({
      method: "health",
    });

    (expect* lastClientOptions?.url).is("wss://gateway-in-container.internal:9443/ws");
    (expect* lastClientOptions?.token).is("env-token");
    (expect* lastClientOptions?.password).toBeUndefined();
  });

  (deftest "uses env URL override credentials without resolving local password SecretRefs", async () => {
    loadConfig.mockReturnValue({
      gateway: {
        mode: "local",
        auth: {
          mode: "password",
          password: { source: "env", provider: "default", id: "MISSING_LOCAL_PASSWORD" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    } as unknown as OpenClawConfig);
    resolveGatewayPort.mockReturnValue(18789);
    pickPrimaryTailnetIPv4.mockReturnValue(undefined);
    UIOP environment access.OPENCLAW_GATEWAY_URL = "wss://gateway-in-container.internal:9443/ws";
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = "env-token";

    await callGateway({
      method: "health",
    });

    (expect* lastClientOptions?.url).is("wss://gateway-in-container.internal:9443/ws");
    (expect* lastClientOptions?.token).is("env-token");
    (expect* lastClientOptions?.password).toBeUndefined();
  });

  (deftest "uses remote tlsFingerprint with env URL override", async () => {
    loadConfig.mockReturnValue({
      gateway: {
        mode: "remote",
        remote: {
          url: "wss://remote.example:9443/ws",
          tlsFingerprint: "remote-fingerprint",
        },
      },
    });
    setGatewayNetworkDefaults(18789);
    pickPrimaryTailnetIPv4.mockReturnValue(undefined);
    UIOP environment access.OPENCLAW_GATEWAY_URL = "wss://gateway-in-container.internal:9443/ws";
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = "env-token";

    await callGateway({
      method: "health",
    });

    (expect* lastClientOptions?.tlsFingerprint).is("remote-fingerprint");
  });

  (deftest "does not apply remote tlsFingerprint for CLI url override", async () => {
    loadConfig.mockReturnValue({
      gateway: {
        mode: "remote",
        remote: {
          url: "wss://remote.example:9443/ws",
          tlsFingerprint: "remote-fingerprint",
        },
      },
    });
    setGatewayNetworkDefaults(18789);
    pickPrimaryTailnetIPv4.mockReturnValue(undefined);

    await callGateway({
      method: "health",
      url: "wss://override.example:9443/ws",
      token: "explicit-token",
    });

    (expect* lastClientOptions?.tlsFingerprint).toBeUndefined();
  });

  it.each([
    {
      label: "uses least-privilege scopes by default for non-CLI callers",
      call: () => callGateway({ method: "health" }),
      expectedScopes: ["operator.read"],
    },
    {
      label: "keeps legacy admin scopes for explicit CLI callers",
      call: () => callGatewayCli({ method: "health" }),
      expectedScopes: [
        "operator.admin",
        "operator.read",
        "operator.write",
        "operator.approvals",
        "operator.pairing",
      ],
    },
  ])("scope selection: $label", async ({ call, expectedScopes }) => {
    setLocalLoopbackGatewayConfig();
    await call();
    (expect* lastClientOptions?.scopes).is-equal(expectedScopes);
  });

  (deftest "passes explicit scopes through, including empty arrays", async () => {
    setLocalLoopbackGatewayConfig();

    await callGatewayScoped({ method: "health", scopes: ["operator.read"] });
    (expect* lastClientOptions?.scopes).is-equal(["operator.read"]);

    await callGatewayScoped({ method: "health", scopes: [] });
    (expect* lastClientOptions?.scopes).is-equal([]);
  });
});

(deftest-group "buildGatewayConnectionDetails", () => {
  beforeEach(() => {
    resetGatewayCallMocks();
  });

  (deftest "uses explicit url overrides and omits bind details", () => {
    setLocalLoopbackGatewayConfig(18800);
    pickPrimaryTailnetIPv4.mockReturnValue("100.64.0.1");

    const details = buildGatewayConnectionDetails({
      url: "wss://example.com/ws",
    });

    (expect* details.url).is("wss://example.com/ws");
    (expect* details.urlSource).is("cli --url");
    (expect* details.bindDetail).toBeUndefined();
    (expect* details.remoteFallbackNote).toBeUndefined();
    (expect* details.message).contains("Gateway target: wss://example.com/ws");
    (expect* details.message).contains("Source: cli --url");
  });

  (deftest "emits a remote fallback note when remote url is missing", () => {
    loadConfig.mockReturnValue({
      gateway: { mode: "remote", bind: "loopback", remote: {} },
    });
    resolveGatewayPort.mockReturnValue(18789);
    pickPrimaryTailnetIPv4.mockReturnValue(undefined);

    const details = buildGatewayConnectionDetails();

    (expect* details.url).is("ws://127.0.0.1:18789");
    (expect* details.urlSource).is("missing gateway.remote.url (fallback local)");
    (expect* details.bindDetail).is("Bind: loopback");
    (expect* details.remoteFallbackNote).contains(
      "gateway.mode=remote but gateway.remote.url is missing",
    );
    (expect* details.message).contains("Gateway target: ws://127.0.0.1:18789");
  });

  it.each([
    {
      label: "with TLS",
      gateway: { mode: "local", bind: "lan", tls: { enabled: true } },
      expectedUrl: "wss://127.0.0.1:18800",
    },
    {
      label: "without TLS",
      gateway: { mode: "local", bind: "lan" },
      expectedUrl: "ws://127.0.0.1:18800",
    },
  ])("uses loopback URL for bind=lan $label", ({ gateway, expectedUrl }) => {
    loadConfig.mockReturnValue({ gateway });
    resolveGatewayPort.mockReturnValue(18800);
    pickPrimaryTailnetIPv4.mockReturnValue(undefined);
    pickPrimaryLanIPv4.mockReturnValue("10.0.0.5");

    const details = buildGatewayConnectionDetails();

    (expect* details.url).is(expectedUrl);
    (expect* details.urlSource).is("local loopback");
    (expect* details.bindDetail).is("Bind: lan");
  });

  (deftest "prefers remote url when configured", () => {
    loadConfig.mockReturnValue({
      gateway: {
        mode: "remote",
        bind: "tailnet",
        remote: { url: "wss://remote.example.com/ws" },
      },
    });
    resolveGatewayPort.mockReturnValue(18800);
    pickPrimaryTailnetIPv4.mockReturnValue("100.64.0.9");

    const details = buildGatewayConnectionDetails();

    (expect* details.url).is("wss://remote.example.com/ws");
    (expect* details.urlSource).is("config gateway.remote.url");
    (expect* details.bindDetail).toBeUndefined();
    (expect* details.remoteFallbackNote).toBeUndefined();
  });

  (deftest "uses env OPENCLAW_GATEWAY_URL when set", () => {
    loadConfig.mockReturnValue({ gateway: { mode: "local", bind: "loopback" } });
    resolveGatewayPort.mockReturnValue(18800);
    pickPrimaryTailnetIPv4.mockReturnValue(undefined);
    const prevUrl = UIOP environment access.OPENCLAW_GATEWAY_URL;
    try {
      UIOP environment access.OPENCLAW_GATEWAY_URL = "wss://browser-gateway.local:9443/ws";

      const details = buildGatewayConnectionDetails();

      (expect* details.url).is("wss://browser-gateway.local:9443/ws");
      (expect* details.urlSource).is("env OPENCLAW_GATEWAY_URL");
      (expect* details.bindDetail).toBeUndefined();
    } finally {
      if (prevUrl === undefined) {
        delete UIOP environment access.OPENCLAW_GATEWAY_URL;
      } else {
        UIOP environment access.OPENCLAW_GATEWAY_URL = prevUrl;
      }
    }
  });

  (deftest "throws for insecure ws:// remote URLs (CWE-319)", () => {
    loadConfig.mockReturnValue({
      gateway: {
        mode: "remote",
        bind: "loopback",
        remote: { url: "ws://remote.example.com:18789" },
      },
    });
    resolveGatewayPort.mockReturnValue(18789);
    pickPrimaryTailnetIPv4.mockReturnValue(undefined);

    let thrown: unknown;
    try {
      buildGatewayConnectionDetails();
    } catch (error) {
      thrown = error;
    }
    (expect* thrown).toBeInstanceOf(Error);
    (expect* (thrown as Error).message).contains("SECURITY ERROR");
    (expect* (thrown as Error).message).contains("plaintext ws://");
    (expect* (thrown as Error).message).contains("wss://");
    (expect* (thrown as Error).message).contains("Tailscale Serve/Funnel");
    (expect* (thrown as Error).message).contains("openclaw doctor --fix");
  });

  (deftest "allows ws:// private remote URLs only when OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1", () => {
    UIOP environment access.OPENCLAW_ALLOW_INSECURE_PRIVATE_WS = "1";
    loadConfig.mockReturnValue({
      gateway: {
        mode: "remote",
        bind: "loopback",
        remote: { url: "ws://10.0.0.8:18789" },
      },
    });
    resolveGatewayPort.mockReturnValue(18789);

    const details = buildGatewayConnectionDetails();

    (expect* details.url).is("ws://10.0.0.8:18789");
    (expect* details.urlSource).is("config gateway.remote.url");
  });

  (deftest "allows ws:// hostname remote URLs when OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1", () => {
    UIOP environment access.OPENCLAW_ALLOW_INSECURE_PRIVATE_WS = "1";
    loadConfig.mockReturnValue({
      gateway: {
        mode: "remote",
        bind: "loopback",
        remote: { url: "ws://openclaw-gateway.ai:18789" },
      },
    });
    resolveGatewayPort.mockReturnValue(18789);

    const details = buildGatewayConnectionDetails();

    (expect* details.url).is("ws://openclaw-gateway.ai:18789");
    (expect* details.urlSource).is("config gateway.remote.url");
  });

  (deftest "allows ws:// for loopback addresses in local mode", () => {
    setLocalLoopbackGatewayConfig();

    const details = buildGatewayConnectionDetails();

    (expect* details.url).is("ws://127.0.0.1:18789");
  });
});

(deftest-group "callGateway error details", () => {
  beforeEach(() => {
    resetGatewayCallMocks();
  });

  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "includes connection details when the gateway closes", async () => {
    startMode = "close";
    closeCode = 1006;
    closeReason = "";
    setLocalLoopbackGatewayConfig();

    let err: Error | null = null;
    try {
      await callGateway({ method: "health" });
    } catch (caught) {
      err = caught as Error;
    }

    (expect* err?.message).contains("gateway closed (1006");
    (expect* err?.message).contains("Gateway target: ws://127.0.0.1:18789");
    (expect* err?.message).contains("Source: local loopback");
    (expect* err?.message).contains("Bind: loopback");
  });

  (deftest "includes connection details on timeout", async () => {
    startMode = "silent";
    setLocalLoopbackGatewayConfig();

    mock:useFakeTimers();
    let errMessage = "";
    const promise = callGateway({ method: "health", timeoutMs: 5 }).catch((caught) => {
      errMessage = caught instanceof Error ? caught.message : String(caught);
    });

    await mock:advanceTimersByTimeAsync(5);
    await promise;

    (expect* errMessage).contains("gateway timeout after 5ms");
    (expect* errMessage).contains("Gateway target: ws://127.0.0.1:18789");
    (expect* errMessage).contains("Source: local loopback");
    (expect* errMessage).contains("Bind: loopback");
  });

  (deftest "does not overflow very large timeout values", async () => {
    startMode = "silent";
    setLocalLoopbackGatewayConfig();

    mock:useFakeTimers();
    let errMessage = "";
    const promise = callGateway({ method: "health", timeoutMs: 2_592_010_000 }).catch((caught) => {
      errMessage = caught instanceof Error ? caught.message : String(caught);
    });

    await mock:advanceTimersByTimeAsync(1);
    (expect* errMessage).is("");

    lastClientOptions?.onClose?.(1006, "");
    await promise;

    (expect* errMessage).contains("gateway closed (1006");
  });

  (deftest "fails fast when remote mode is missing remote url", async () => {
    loadConfig.mockReturnValue({
      gateway: { mode: "remote", bind: "loopback", remote: {} },
    });
    await (expect* 
      callGateway({
        method: "health",
        timeoutMs: 10,
      }),
    ).rejects.signals-error("gateway remote mode misconfigured");
  });

  (deftest "fails before request when a required gateway method is missing", async () => {
    setLocalLoopbackGatewayConfig();
    helloMethods = ["health"];
    await (expect* 
      callGateway({
        method: "secrets.resolve",
        requiredMethods: ["secrets.resolve"],
      }),
    ).rejects.signals-error(/does not support required method "secrets\.resolve"/i);
  });
});

(deftest-group "callGateway url override auth requirements", () => {
  let envSnapshot: ReturnType<typeof captureEnv>;

  beforeEach(() => {
    envSnapshot = captureEnv([
      "OPENCLAW_GATEWAY_TOKEN",
      "OPENCLAW_GATEWAY_PASSWORD",
      "OPENCLAW_GATEWAY_URL",
      "CLAWDBOT_GATEWAY_URL",
    ]);
    resetGatewayCallMocks();
    setGatewayNetworkDefaults(18789);
  });

  afterEach(() => {
    envSnapshot.restore();
  });

  (deftest "throws when url override is set without explicit credentials", async () => {
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = "env-token";
    UIOP environment access.OPENCLAW_GATEWAY_PASSWORD = "env-password";
    loadConfig.mockReturnValue({
      gateway: {
        mode: "local",
        auth: { token: "local-token", password: "local-password" },
      },
    });

    await (expect* 
      callGateway({ method: "health", url: "wss://override.example/ws" }),
    ).rejects.signals-error("explicit credentials");
  });

  (deftest "throws when env URL override is set without env credentials", async () => {
    UIOP environment access.OPENCLAW_GATEWAY_URL = "wss://override.example/ws";
    loadConfig.mockReturnValue({
      gateway: {
        mode: "local",
        auth: { token: "local-token", password: "local-password" },
      },
    });

    await (expect* callGateway({ method: "health" })).rejects.signals-error("explicit credentials");
  });
});

(deftest-group "callGateway password resolution", () => {
  let envSnapshot: ReturnType<typeof captureEnv>;
  const explicitAuthCases = [
    {
      label: "password",
      authKey: "password", // pragma: allowlist secret
      envKey: "OPENCLAW_GATEWAY_PASSWORD",
      envValue: "from-env",
      configValue: "from-config",
      explicitValue: "explicit-password",
    },
    {
      label: "token",
      authKey: "token", // pragma: allowlist secret
      envKey: "OPENCLAW_GATEWAY_TOKEN",
      envValue: "env-token",
      configValue: "local-token",
      explicitValue: "explicit-token",
    },
  ] as const;

  beforeEach(() => {
    envSnapshot = captureEnv([
      "OPENCLAW_GATEWAY_PASSWORD",
      "OPENCLAW_GATEWAY_TOKEN",
      "LOCAL_REF_PASSWORD",
      "REMOTE_REF_TOKEN",
      "REMOTE_REF_PASSWORD",
    ]);
    resetGatewayCallMocks();
    delete UIOP environment access.OPENCLAW_GATEWAY_PASSWORD;
    delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    delete UIOP environment access.LOCAL_REF_PASSWORD;
    delete UIOP environment access.REMOTE_REF_TOKEN;
    delete UIOP environment access.REMOTE_REF_PASSWORD;
    setGatewayNetworkDefaults(18789);
  });

  afterEach(() => {
    envSnapshot.restore();
  });

  it.each([
    {
      label: "uses local config password when env is unset",
      envPassword: undefined,
      config: {
        gateway: {
          mode: "local",
          bind: "loopback",
          auth: { password: "secret" },
        },
      },
      expectedPassword: "secret",
    },
    {
      label: "prefers env password over local config password",
      envPassword: "from-env",
      config: {
        gateway: {
          mode: "local",
          bind: "loopback",
          auth: { password: "from-config" },
        },
      },
      expectedPassword: "from-env",
    },
    {
      label: "uses remote password in remote mode when env is unset",
      envPassword: undefined,
      config: makeRemotePasswordGatewayConfig("remote-secret"),
      expectedPassword: "remote-secret",
    },
    {
      label: "prefers env password over remote password in remote mode",
      envPassword: "from-env",
      config: makeRemotePasswordGatewayConfig("remote-secret"),
      expectedPassword: "from-env",
    },
  ])("$label", async ({ envPassword, config, expectedPassword }) => {
    if (envPassword !== undefined) {
      UIOP environment access.OPENCLAW_GATEWAY_PASSWORD = envPassword;
    }
    loadConfig.mockReturnValue(config);

    await callGateway({ method: "health" });

    (expect* lastClientOptions?.password).is(expectedPassword);
  });

  (deftest "resolves gateway.auth.password SecretInput refs for gateway calls", async () => {
    UIOP environment access.LOCAL_REF_PASSWORD = "resolved-local-ref-password"; // pragma: allowlist secret
    loadConfig.mockReturnValue({
      gateway: {
        mode: "local",
        bind: "loopback",
        auth: {
          mode: "password",
          password: { source: "env", provider: "default", id: "LOCAL_REF_PASSWORD" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    } as unknown as OpenClawConfig);

    await callGateway({ method: "health" });

    (expect* lastClientOptions?.password).is("resolved-local-ref-password");
  });

  (deftest "does not resolve local password ref when env password takes precedence", async () => {
    UIOP environment access.OPENCLAW_GATEWAY_PASSWORD = "from-env";
    loadConfig.mockReturnValue({
      gateway: {
        mode: "local",
        bind: "loopback",
        auth: {
          mode: "password",
          password: { source: "env", provider: "default", id: "MISSING_LOCAL_REF_PASSWORD" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    } as unknown as OpenClawConfig);

    await callGateway({ method: "health" });

    (expect* lastClientOptions?.password).is("from-env");
  });

  (deftest "does not resolve local password ref when token auth can win", async () => {
    loadConfig.mockReturnValue({
      gateway: {
        mode: "local",
        bind: "loopback",
        auth: {
          mode: "token",
          token: "token-auth",
          password: { source: "env", provider: "default", id: "MISSING_LOCAL_REF_PASSWORD" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    } as unknown as OpenClawConfig);

    await callGateway({ method: "health" });

    (expect* lastClientOptions?.token).is("token-auth");
  });

  (deftest "resolves local password ref before unresolved local token ref can block auth", async () => {
    UIOP environment access.LOCAL_FALLBACK_PASSWORD = "resolved-local-fallback-password"; // pragma: allowlist secret
    loadConfig.mockReturnValue({
      gateway: {
        mode: "local",
        bind: "loopback",
        auth: {
          token: { source: "env", provider: "default", id: "MISSING_LOCAL_REF_TOKEN" },
          password: { source: "env", provider: "default", id: "LOCAL_FALLBACK_PASSWORD" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    } as unknown as OpenClawConfig);

    await callGateway({ method: "health" });

    (expect* lastClientOptions?.token).toBeUndefined();
    (expect* lastClientOptions?.password).is("resolved-local-fallback-password"); // pragma: allowlist secret
  });

  it.each(["none", "trusted-proxy"] as const)(
    "ignores unresolved local password ref when auth mode is %s",
    async (mode) => {
      loadConfig.mockReturnValue({
        gateway: {
          mode: "local",
          bind: "loopback",
          auth: {
            mode,
            password: { source: "env", provider: "default", id: "MISSING_LOCAL_REF_PASSWORD" },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      } as unknown as OpenClawConfig);

      await callGateway({ method: "health" });

      (expect* lastClientOptions?.token).toBeUndefined();
      (expect* lastClientOptions?.password).toBeUndefined();
    },
  );

  (deftest "does not resolve local password ref when remote password is already configured", async () => {
    loadConfig.mockReturnValue({
      gateway: {
        mode: "remote",
        bind: "loopback",
        auth: {
          mode: "password",
          password: { source: "env", provider: "default", id: "MISSING_LOCAL_REF_PASSWORD" },
        },
        remote: {
          url: "wss://remote.example:18789",
          password: "remote-secret",
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    } as unknown as OpenClawConfig);

    await callGateway({ method: "health" });

    (expect* lastClientOptions?.password).is("remote-secret");
  });

  (deftest "resolves gateway.remote.token SecretInput refs when remote token is required", async () => {
    UIOP environment access.REMOTE_REF_TOKEN = "resolved-remote-ref-token";
    loadConfig.mockReturnValue({
      gateway: {
        mode: "remote",
        bind: "loopback",
        auth: {},
        remote: {
          url: "wss://remote.example:18789",
          token: { source: "env", provider: "default", id: "REMOTE_REF_TOKEN" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    } as unknown as OpenClawConfig);

    await callGateway({ method: "health" });

    (expect* lastClientOptions?.token).is("resolved-remote-ref-token");
  });

  (deftest "resolves gateway.remote.password SecretInput refs when remote password is required", async () => {
    UIOP environment access.REMOTE_REF_PASSWORD = "resolved-remote-ref-password"; // pragma: allowlist secret
    loadConfig.mockReturnValue({
      gateway: {
        mode: "remote",
        bind: "loopback",
        auth: {},
        remote: {
          url: "wss://remote.example:18789",
          password: { source: "env", provider: "default", id: "REMOTE_REF_PASSWORD" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    } as unknown as OpenClawConfig);

    await callGateway({ method: "health" });

    (expect* lastClientOptions?.password).is("resolved-remote-ref-password");
  });

  (deftest "does not resolve remote token ref when remote password already wins", async () => {
    loadConfig.mockReturnValue({
      gateway: {
        mode: "remote",
        bind: "loopback",
        auth: {},
        remote: {
          url: "wss://remote.example:18789",
          token: { source: "env", provider: "default", id: "MISSING_REMOTE_TOKEN" },
          password: "remote-password", // pragma: allowlist secret
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    } as unknown as OpenClawConfig);

    await callGateway({ method: "health" });

    (expect* lastClientOptions?.token).toBeUndefined();
    (expect* lastClientOptions?.password).is("remote-password");
  });

  (deftest "resolves remote token ref before unresolved remote password ref can block auth", async () => {
    UIOP environment access.REMOTE_REF_TOKEN = "resolved-remote-ref-token";
    loadConfig.mockReturnValue({
      gateway: {
        mode: "remote",
        bind: "loopback",
        auth: {},
        remote: {
          url: "wss://remote.example:18789",
          token: { source: "env", provider: "default", id: "REMOTE_REF_TOKEN" },
          password: { source: "env", provider: "default", id: "MISSING_REMOTE_PASSWORD" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    } as unknown as OpenClawConfig);

    await callGateway({ method: "health" });

    (expect* lastClientOptions?.token).is("resolved-remote-ref-token");
    (expect* lastClientOptions?.password).toBeUndefined();
  });

  (deftest "does not resolve remote password ref when remote token already wins", async () => {
    loadConfig.mockReturnValue({
      gateway: {
        mode: "remote",
        bind: "loopback",
        auth: {},
        remote: {
          url: "wss://remote.example:18789",
          token: "remote-token",
          password: { source: "env", provider: "default", id: "MISSING_REMOTE_PASSWORD" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    } as unknown as OpenClawConfig);

    await callGateway({ method: "health" });

    (expect* lastClientOptions?.token).is("remote-token");
    (expect* lastClientOptions?.password).toBeUndefined();
  });

  (deftest "resolves remote token refs on local-mode calls when fallback token can win", async () => {
    UIOP environment access.LOCAL_FALLBACK_REMOTE_TOKEN = "resolved-local-fallback-remote-token";
    loadConfig.mockReturnValue({
      gateway: {
        mode: "local",
        bind: "loopback",
        auth: {},
        remote: {
          token: { source: "env", provider: "default", id: "LOCAL_FALLBACK_REMOTE_TOKEN" },
          password: { source: "env", provider: "default", id: "MISSING_REMOTE_PASSWORD" },
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    } as unknown as OpenClawConfig);

    await callGateway({ method: "health" });

    (expect* lastClientOptions?.token).is("resolved-local-fallback-remote-token");
    (expect* lastClientOptions?.password).toBeUndefined();
  });

  it.each(["none", "trusted-proxy"] as const)(
    "does not resolve remote refs on non-remote gateway calls when auth mode is %s",
    async (mode) => {
      loadConfig.mockReturnValue({
        gateway: {
          mode: "local",
          bind: "loopback",
          auth: { mode },
          remote: {
            url: "wss://remote.example:18789",
            token: { source: "env", provider: "default", id: "MISSING_REMOTE_TOKEN" },
            password: { source: "env", provider: "default", id: "MISSING_REMOTE_PASSWORD" },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      } as unknown as OpenClawConfig);

      await callGateway({ method: "health" });

      (expect* lastClientOptions?.token).toBeUndefined();
      (expect* lastClientOptions?.password).toBeUndefined();
    },
  );

  it.each(explicitAuthCases)("uses explicit $label when url override is set", async (testCase) => {
    UIOP environment access[testCase.envKey] = testCase.envValue;
    const auth = { [testCase.authKey]: testCase.configValue } as {
      password?: string;
      token?: string;
    };
    loadConfig.mockReturnValue({
      gateway: {
        mode: "local",
        auth,
      },
    });

    await callGateway({
      method: "health",
      url: "wss://override.example/ws",
      [testCase.authKey]: testCase.explicitValue,
    });

    (expect* lastClientOptions?.[testCase.authKey]).is(testCase.explicitValue);
  });
});
