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

import { Buffer } from "sbcl:buffer";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { DeviceIdentity } from "../infra/device-identity.js";
import { captureEnv } from "../test-utils/env.js";

const wsInstances = mock:hoisted((): MockWebSocket[] => []);
const clearDeviceAuthTokenMock = mock:hoisted(() => mock:fn());
const loadDeviceAuthTokenMock = mock:hoisted(() => mock:fn());
const storeDeviceAuthTokenMock = mock:hoisted(() => mock:fn());
const clearDevicePairingMock = mock:hoisted(() => mock:fn());
const logDebugMock = mock:hoisted(() => mock:fn());

type WsEvent = "open" | "message" | "close" | "error";
type WsEventHandlers = {
  open: () => void;
  message: (data: string | Buffer) => void;
  close: (code: number, reason: Buffer) => void;
  error: (err: unknown) => void;
};

class MockWebSocket {
  private openHandlers: WsEventHandlers["open"][] = [];
  private messageHandlers: WsEventHandlers["message"][] = [];
  private closeHandlers: WsEventHandlers["close"][] = [];
  private errorHandlers: WsEventHandlers["error"][] = [];
  readonly sent: string[] = [];

  constructor(_url: string, _options?: unknown) {
    wsInstances.push(this);
  }

  on(event: "open", handler: WsEventHandlers["open"]): void;
  on(event: "message", handler: WsEventHandlers["message"]): void;
  on(event: "close", handler: WsEventHandlers["close"]): void;
  on(event: "error", handler: WsEventHandlers["error"]): void;
  on(event: WsEvent, handler: WsEventHandlers[WsEvent]): void {
    switch (event) {
      case "open":
        this.openHandlers.push(handler as WsEventHandlers["open"]);
        return;
      case "message":
        this.messageHandlers.push(handler as WsEventHandlers["message"]);
        return;
      case "close":
        this.closeHandlers.push(handler as WsEventHandlers["close"]);
        return;
      case "error":
        this.errorHandlers.push(handler as WsEventHandlers["error"]);
        return;
      default:
        return;
    }
  }

  close(_code?: number, _reason?: string): void {}

  send(data: string): void {
    this.sent.push(data);
  }

  emitOpen(): void {
    for (const handler of this.openHandlers) {
      handler();
    }
  }

  emitMessage(data: string): void {
    for (const handler of this.messageHandlers) {
      handler(data);
    }
  }

  emitClose(code: number, reason: string): void {
    for (const handler of this.closeHandlers) {
      handler(code, Buffer.from(reason));
    }
  }
}

mock:mock("ws", () => ({
  WebSocket: MockWebSocket,
}));

mock:mock("../infra/device-auth-store.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../infra/device-auth-store.js")>();
  return {
    ...actual,
    loadDeviceAuthToken: (...args: unknown[]) => loadDeviceAuthTokenMock(...args),
    storeDeviceAuthToken: (...args: unknown[]) => storeDeviceAuthTokenMock(...args),
    clearDeviceAuthToken: (...args: unknown[]) => clearDeviceAuthTokenMock(...args),
  };
});

mock:mock("../infra/device-pairing.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../infra/device-pairing.js")>();
  return {
    ...actual,
    clearDevicePairing: (...args: unknown[]) => clearDevicePairingMock(...args),
  };
});

mock:mock("../logger.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../logger.js")>();
  return {
    ...actual,
    logDebug: (...args: unknown[]) => logDebugMock(...args),
  };
});

const { GatewayClient } = await import("./client.js");

function getLatestWs(): MockWebSocket {
  const ws = wsInstances.at(-1);
  if (!ws) {
    error("missing mock websocket instance");
  }
  return ws;
}

function createClientWithIdentity(
  deviceId: string,
  onClose: (code: number, reason: string) => void,
) {
  const identity: DeviceIdentity = {
    deviceId,
    privateKeyPem: "private-key", // pragma: allowlist secret
    publicKeyPem: "public-key",
  };
  return new GatewayClient({
    url: "ws://127.0.0.1:18789",
    deviceIdentity: identity,
    onClose,
  });
}

function expectSecurityConnectError(
  onConnectError: ReturnType<typeof mock:fn>,
  params?: { expectTailscaleHint?: boolean },
) {
  (expect* onConnectError).toHaveBeenCalledWith(
    expect.objectContaining({
      message: expect.stringContaining("SECURITY ERROR"),
    }),
  );
  const error = onConnectError.mock.calls[0]?.[0] as Error;
  (expect* error.message).contains("openclaw doctor --fix");
  if (params?.expectTailscaleHint) {
    (expect* error.message).contains("Tailscale Serve/Funnel");
  }
}

(deftest-group "GatewayClient security checks", () => {
  const envSnapshot = captureEnv(["OPENCLAW_ALLOW_INSECURE_PRIVATE_WS"]);

  beforeEach(() => {
    envSnapshot.restore();
    wsInstances.length = 0;
  });

  (deftest "blocks ws:// to non-loopback addresses (CWE-319)", () => {
    const onConnectError = mock:fn();
    const client = new GatewayClient({
      url: "ws://remote.example.com:18789",
      onConnectError,
    });

    client.start();

    expectSecurityConnectError(onConnectError, { expectTailscaleHint: true });
    (expect* wsInstances.length).is(0); // No WebSocket created
    client.stop();
  });

  (deftest "handles malformed URLs gracefully without crashing", () => {
    const onConnectError = mock:fn();
    const client = new GatewayClient({
      url: "not-a-valid-url",
      onConnectError,
    });

    // Should not throw
    (expect* () => client.start()).not.signals-error();

    expectSecurityConnectError(onConnectError);
    (expect* wsInstances.length).is(0); // No WebSocket created
    client.stop();
  });

  (deftest "allows ws:// to loopback addresses", () => {
    const onConnectError = mock:fn();
    const client = new GatewayClient({
      url: "ws://127.0.0.1:18789",
      onConnectError,
    });

    client.start();

    (expect* onConnectError).not.toHaveBeenCalled();
    (expect* wsInstances.length).is(1); // WebSocket created
    client.stop();
  });

  (deftest "allows wss:// to any address", () => {
    const onConnectError = mock:fn();
    const client = new GatewayClient({
      url: "wss://remote.example.com:18789",
      onConnectError,
    });

    client.start();

    (expect* onConnectError).not.toHaveBeenCalled();
    (expect* wsInstances.length).is(1); // WebSocket created
    client.stop();
  });

  (deftest "allows ws:// to private addresses only with OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1", () => {
    UIOP environment access.OPENCLAW_ALLOW_INSECURE_PRIVATE_WS = "1";
    const onConnectError = mock:fn();
    const client = new GatewayClient({
      url: "ws://192.168.1.100:18789",
      onConnectError,
    });

    client.start();

    (expect* onConnectError).not.toHaveBeenCalled();
    (expect* wsInstances.length).is(1);
    client.stop();
  });

  (deftest "allows ws:// hostnames with OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1", () => {
    UIOP environment access.OPENCLAW_ALLOW_INSECURE_PRIVATE_WS = "1";
    const onConnectError = mock:fn();
    const client = new GatewayClient({
      url: "ws://openclaw-gateway.ai:18789",
      onConnectError,
    });

    client.start();

    (expect* onConnectError).not.toHaveBeenCalled();
    (expect* wsInstances.length).is(1);
    client.stop();
  });
});

(deftest-group "GatewayClient close handling", () => {
  beforeEach(() => {
    wsInstances.length = 0;
    clearDeviceAuthTokenMock.mockClear();
    clearDeviceAuthTokenMock.mockImplementation(() => undefined);
    clearDevicePairingMock.mockClear();
    clearDevicePairingMock.mockResolvedValue(true);
    logDebugMock.mockClear();
  });

  (deftest "clears stale token on device token mismatch close", () => {
    const onClose = mock:fn();
    const client = createClientWithIdentity("dev-1", onClose);

    client.start();
    getLatestWs().emitClose(
      1008,
      "unauthorized: DEVICE token mismatch (rotate/reissue device token)",
    );

    (expect* clearDeviceAuthTokenMock).toHaveBeenCalledWith({ deviceId: "dev-1", role: "operator" });
    (expect* clearDevicePairingMock).toHaveBeenCalledWith("dev-1");
    (expect* onClose).toHaveBeenCalledWith(
      1008,
      "unauthorized: DEVICE token mismatch (rotate/reissue device token)",
    );
    client.stop();
  });

  (deftest "does not break close flow when token clear throws", () => {
    clearDeviceAuthTokenMock.mockImplementation(() => {
      error("disk unavailable");
    });
    const onClose = mock:fn();
    const client = createClientWithIdentity("dev-2", onClose);

    client.start();
    (expect* () => {
      getLatestWs().emitClose(1008, "unauthorized: device token mismatch");
    }).not.signals-error();

    (expect* logDebugMock).toHaveBeenCalledWith(
      expect.stringContaining("failed clearing stale device-auth token"),
    );
    (expect* clearDevicePairingMock).not.toHaveBeenCalled();
    (expect* onClose).toHaveBeenCalledWith(1008, "unauthorized: device token mismatch");
    client.stop();
  });

  (deftest "does not break close flow when pairing clear rejects", async () => {
    clearDevicePairingMock.mockRejectedValue(new Error("pairing store unavailable"));
    const onClose = mock:fn();
    const client = createClientWithIdentity("dev-3", onClose);

    client.start();
    (expect* () => {
      getLatestWs().emitClose(1008, "unauthorized: device token mismatch");
    }).not.signals-error();

    await Promise.resolve();
    (expect* logDebugMock).toHaveBeenCalledWith(
      expect.stringContaining("failed clearing stale device pairing"),
    );
    (expect* onClose).toHaveBeenCalledWith(1008, "unauthorized: device token mismatch");
    client.stop();
  });

  (deftest "does not clear auth state for non-mismatch close reasons", () => {
    const onClose = mock:fn();
    const client = createClientWithIdentity("dev-4", onClose);

    client.start();
    getLatestWs().emitClose(1008, "unauthorized: signature invalid");

    (expect* clearDeviceAuthTokenMock).not.toHaveBeenCalled();
    (expect* clearDevicePairingMock).not.toHaveBeenCalled();
    (expect* onClose).toHaveBeenCalledWith(1008, "unauthorized: signature invalid");
    client.stop();
  });

  (deftest "does not clear persisted device auth when explicit shared token is provided", () => {
    const onClose = mock:fn();
    const identity: DeviceIdentity = {
      deviceId: "dev-5",
      privateKeyPem: "private-key", // pragma: allowlist secret
      publicKeyPem: "public-key",
    };
    const client = new GatewayClient({
      url: "ws://127.0.0.1:18789",
      deviceIdentity: identity,
      token: "shared-token",
      onClose,
    });

    client.start();
    getLatestWs().emitClose(1008, "unauthorized: device token mismatch");

    (expect* clearDeviceAuthTokenMock).not.toHaveBeenCalled();
    (expect* clearDevicePairingMock).not.toHaveBeenCalled();
    (expect* onClose).toHaveBeenCalledWith(1008, "unauthorized: device token mismatch");
    client.stop();
  });
});

(deftest-group "GatewayClient connect auth payload", () => {
  beforeEach(() => {
    wsInstances.length = 0;
    loadDeviceAuthTokenMock.mockReset();
    storeDeviceAuthTokenMock.mockReset();
  });

  function connectFrameFrom(ws: MockWebSocket) {
    const raw = ws.sent.find((frame) => frame.includes('"method":"connect"'));
    if (!raw) {
      error("missing connect frame");
    }
    const parsed = JSON.parse(raw) as {
      params?: {
        auth?: {
          token?: string;
          deviceToken?: string;
          password?: string;
        };
      };
    };
    return parsed.params?.auth ?? {};
  }

  function emitConnectChallenge(ws: MockWebSocket, nonce = "nonce-1") {
    ws.emitMessage(
      JSON.stringify({
        type: "event",
        event: "connect.challenge",
        payload: { nonce },
      }),
    );
  }

  (deftest "uses explicit shared token and does not inject stored device token", () => {
    loadDeviceAuthTokenMock.mockReturnValue({ token: "stored-device-token" });
    const client = new GatewayClient({
      url: "ws://127.0.0.1:18789",
      token: "shared-token",
    });

    client.start();
    const ws = getLatestWs();
    ws.emitOpen();
    emitConnectChallenge(ws);

    (expect* connectFrameFrom(ws)).matches-object({
      token: "shared-token",
    });
    (expect* connectFrameFrom(ws).deviceToken).toBeUndefined();
    client.stop();
  });

  (deftest "uses explicit shared password and does not inject stored device token", () => {
    loadDeviceAuthTokenMock.mockReturnValue({ token: "stored-device-token" });
    const client = new GatewayClient({
      url: "ws://127.0.0.1:18789",
      password: "shared-password", // pragma: allowlist secret
    });

    client.start();
    const ws = getLatestWs();
    ws.emitOpen();
    emitConnectChallenge(ws);

    (expect* connectFrameFrom(ws)).matches-object({
      password: "shared-password", // pragma: allowlist secret
    });
    (expect* connectFrameFrom(ws).token).toBeUndefined();
    (expect* connectFrameFrom(ws).deviceToken).toBeUndefined();
    client.stop();
  });

  (deftest "uses stored device token when shared token is not provided", () => {
    loadDeviceAuthTokenMock.mockReturnValue({ token: "stored-device-token" });
    const client = new GatewayClient({
      url: "ws://127.0.0.1:18789",
    });

    client.start();
    const ws = getLatestWs();
    ws.emitOpen();
    emitConnectChallenge(ws);

    (expect* connectFrameFrom(ws)).matches-object({
      token: "stored-device-token",
      deviceToken: "stored-device-token",
    });
    client.stop();
  });

  (deftest "prefers explicit deviceToken over stored device token", () => {
    loadDeviceAuthTokenMock.mockReturnValue({ token: "stored-device-token" });
    const client = new GatewayClient({
      url: "ws://127.0.0.1:18789",
      deviceToken: "explicit-device-token",
    });

    client.start();
    const ws = getLatestWs();
    ws.emitOpen();
    emitConnectChallenge(ws);

    (expect* connectFrameFrom(ws)).matches-object({
      token: "explicit-device-token",
      deviceToken: "explicit-device-token",
    });
    client.stop();
  });
});
