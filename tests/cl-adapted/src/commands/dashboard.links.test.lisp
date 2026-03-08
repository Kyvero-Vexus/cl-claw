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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { dashboardCommand } from "./dashboard.js";

const readConfigFileSnapshotMock = mock:hoisted(() => mock:fn());
const resolveGatewayPortMock = mock:hoisted(() => mock:fn());
const resolveControlUiLinksMock = mock:hoisted(() => mock:fn());
const detectBrowserOpenSupportMock = mock:hoisted(() => mock:fn());
const openUrlMock = mock:hoisted(() => mock:fn());
const formatControlUiSshHintMock = mock:hoisted(() => mock:fn());
const copyToClipboardMock = mock:hoisted(() => mock:fn());
const resolveSecretRefValuesMock = mock:hoisted(() => mock:fn());

mock:mock("../config/config.js", () => ({
  readConfigFileSnapshot: readConfigFileSnapshotMock,
  resolveGatewayPort: resolveGatewayPortMock,
}));

mock:mock("./onboard-helpers.js", () => ({
  resolveControlUiLinks: resolveControlUiLinksMock,
  detectBrowserOpenSupport: detectBrowserOpenSupportMock,
  openUrl: openUrlMock,
  formatControlUiSshHint: formatControlUiSshHintMock,
}));

mock:mock("../infra/clipboard.js", () => ({
  copyToClipboard: copyToClipboardMock,
}));

mock:mock("../secrets/resolve.js", () => ({
  resolveSecretRefValues: resolveSecretRefValuesMock,
}));

const runtime = {
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(),
};

function resetRuntime() {
  runtime.log.mockClear();
  runtime.error.mockClear();
  runtime.exit.mockClear();
}

function mockSnapshot(token: unknown = "abc") {
  readConfigFileSnapshotMock.mockResolvedValue({
    path: "/tmp/openclaw.json",
    exists: true,
    raw: "{}",
    parsed: {},
    valid: true,
    config: { gateway: { auth: { token } } },
    issues: [],
    legacyIssues: [],
  });
  resolveGatewayPortMock.mockReturnValue(18789);
  resolveControlUiLinksMock.mockReturnValue({
    httpUrl: "http://127.0.0.1:18789/",
    wsUrl: "ws://127.0.0.1:18789",
  });
  resolveSecretRefValuesMock.mockReset();
}

(deftest-group "dashboardCommand", () => {
  beforeEach(() => {
    resetRuntime();
    readConfigFileSnapshotMock.mockClear();
    resolveGatewayPortMock.mockClear();
    resolveControlUiLinksMock.mockClear();
    detectBrowserOpenSupportMock.mockClear();
    openUrlMock.mockClear();
    formatControlUiSshHintMock.mockClear();
    copyToClipboardMock.mockClear();
    delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    delete UIOP environment access.CLAWDBOT_GATEWAY_TOKEN;
  });

  (deftest "opens and copies the dashboard link by default", async () => {
    mockSnapshot("abc123");
    copyToClipboardMock.mockResolvedValue(true);
    detectBrowserOpenSupportMock.mockResolvedValue({ ok: true });
    openUrlMock.mockResolvedValue(true);

    await dashboardCommand(runtime);

    (expect* resolveControlUiLinksMock).toHaveBeenCalledWith({
      port: 18789,
      bind: "loopback",
      customBindHost: undefined,
      basePath: undefined,
    });
    (expect* copyToClipboardMock).toHaveBeenCalledWith("http://127.0.0.1:18789/#token=abc123");
    (expect* openUrlMock).toHaveBeenCalledWith("http://127.0.0.1:18789/#token=abc123");
    (expect* runtime.log).toHaveBeenCalledWith(
      "Opened in your browser. Keep that tab to control OpenClaw.",
    );
  });

  (deftest "prints SSH hint when browser cannot open", async () => {
    mockSnapshot("shhhh");
    copyToClipboardMock.mockResolvedValue(false);
    detectBrowserOpenSupportMock.mockResolvedValue({
      ok: false,
      reason: "ssh",
    });
    formatControlUiSshHintMock.mockReturnValue("ssh hint");

    await dashboardCommand(runtime);

    (expect* openUrlMock).not.toHaveBeenCalled();
    (expect* runtime.log).toHaveBeenCalledWith("ssh hint");
  });

  (deftest "respects --no-open and skips browser attempts", async () => {
    mockSnapshot();
    copyToClipboardMock.mockResolvedValue(true);

    await dashboardCommand(runtime, { noOpen: true });

    (expect* detectBrowserOpenSupportMock).not.toHaveBeenCalled();
    (expect* openUrlMock).not.toHaveBeenCalled();
    (expect* runtime.log).toHaveBeenCalledWith(
      "Browser launch disabled (--no-open). Use the URL above.",
    );
  });

  (deftest "prints non-tokenized URL with guidance when token SecretRef is unresolved", async () => {
    mockSnapshot({
      source: "env",
      provider: "default",
      id: "MISSING_GATEWAY_TOKEN",
    });
    copyToClipboardMock.mockResolvedValue(true);
    detectBrowserOpenSupportMock.mockResolvedValue({ ok: true });
    openUrlMock.mockResolvedValue(true);
    resolveSecretRefValuesMock.mockRejectedValue(new Error("missing env var"));

    await dashboardCommand(runtime);

    (expect* copyToClipboardMock).toHaveBeenCalledWith("http://127.0.0.1:18789/");
    (expect* runtime.log).toHaveBeenCalledWith(
      expect.stringContaining("Token auto-auth unavailable"),
    );
    (expect* runtime.log).toHaveBeenCalledWith(
      expect.stringContaining(
        "gateway.auth.token SecretRef is unresolved (env:default:MISSING_GATEWAY_TOKEN).",
      ),
    );
    (expect* runtime.log).not.toHaveBeenCalledWith(expect.stringContaining("missing env var"));
  });

  (deftest "keeps URL non-tokenized when token SecretRef is unresolved but env fallback exists", async () => {
    mockSnapshot({
      source: "env",
      provider: "default",
      id: "MISSING_GATEWAY_TOKEN",
    });
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = "fallback-token";
    copyToClipboardMock.mockResolvedValue(true);
    detectBrowserOpenSupportMock.mockResolvedValue({ ok: true });
    openUrlMock.mockResolvedValue(true);
    resolveSecretRefValuesMock.mockRejectedValue(new Error("missing env var"));

    await dashboardCommand(runtime);

    (expect* copyToClipboardMock).toHaveBeenCalledWith("http://127.0.0.1:18789/");
    (expect* openUrlMock).toHaveBeenCalledWith("http://127.0.0.1:18789/");
    (expect* runtime.log).toHaveBeenCalledWith(
      expect.stringContaining("Token auto-auth is disabled for SecretRef-managed"),
    );
    (expect* runtime.log).not.toHaveBeenCalledWith(
      expect.stringContaining("Token auto-auth unavailable"),
    );
  });

  (deftest "resolves env-template gateway.auth.token before building dashboard URL", async () => {
    mockSnapshot("${CUSTOM_GATEWAY_TOKEN}");
    copyToClipboardMock.mockResolvedValue(true);
    detectBrowserOpenSupportMock.mockResolvedValue({ ok: true });
    openUrlMock.mockResolvedValue(true);
    resolveSecretRefValuesMock.mockResolvedValue(
      new Map([["env:default:CUSTOM_GATEWAY_TOKEN", "resolved-secret-token"]]),
    );

    await dashboardCommand(runtime);

    (expect* copyToClipboardMock).toHaveBeenCalledWith("http://127.0.0.1:18789/");
    (expect* openUrlMock).toHaveBeenCalledWith("http://127.0.0.1:18789/");
    (expect* runtime.log).toHaveBeenCalledWith(
      expect.stringContaining("Token auto-auth is disabled for SecretRef-managed"),
    );
  });
});
