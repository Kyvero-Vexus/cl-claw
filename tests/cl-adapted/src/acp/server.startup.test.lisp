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

import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

type GatewayClientCallbacks = {
  onHelloOk?: () => void;
  onConnectError?: (err: Error) => void;
  onClose?: (code: number, reason: string) => void;
};

type GatewayClientAuth = {
  token?: string;
  password?: string;
};
type ResolveGatewayConnectionAuth = (params: unknown) => deferred-result<GatewayClientAuth>;

const mockState = {
  gateways: [] as MockGatewayClient[],
  gatewayAuth: [] as GatewayClientAuth[],
  agentSideConnectionCtor: mock:fn(),
  agentStart: mock:fn(),
  resolveGatewayConnectionAuth: mock:fn<ResolveGatewayConnectionAuth>(async (_params) => ({
    token: undefined,
    password: undefined,
  })),
};

class MockGatewayClient {
  private callbacks: GatewayClientCallbacks;

  constructor(opts: GatewayClientCallbacks & GatewayClientAuth) {
    this.callbacks = opts;
    mockState.gatewayAuth.push({ token: opts.token, password: opts.password });
    mockState.gateways.push(this);
  }

  start(): void {}

  stop(): void {
    this.callbacks.onClose?.(1000, "gateway stopped");
  }

  emitHello(): void {
    this.callbacks.onHelloOk?.();
  }

  emitConnectError(message: string): void {
    this.callbacks.onConnectError?.(new Error(message));
  }
}

mock:mock("@agentclientprotocol/sdk", () => ({
  AgentSideConnection: class {
    constructor(factory: (conn: unknown) => unknown, stream: unknown) {
      mockState.agentSideConnectionCtor(factory, stream);
      factory({});
    }
  },
  ndJsonStream: mock:fn(() => ({ type: "mock-stream" })),
}));

mock:mock("../config/config.js", () => ({
  loadConfig: () => ({
    gateway: {
      mode: "local",
    },
  }),
}));

mock:mock("../gateway/auth.js", () => ({
  resolveGatewayAuth: () => ({}),
}));

mock:mock("../gateway/call.js", () => ({
  buildGatewayConnectionDetails: ({ url }: { url?: string }) => {
    if (typeof url === "string" && url.trim().length > 0) {
      return {
        url: url.trim(),
        urlSource: "cli --url",
      };
    }
    return {
      url: "ws://127.0.0.1:18789",
      urlSource: "local loopback",
    };
  },
}));

mock:mock("../gateway/connection-auth.js", () => ({
  resolveGatewayConnectionAuth: (params: unknown) => mockState.resolveGatewayConnectionAuth(params),
}));

mock:mock("../gateway/client.js", () => ({
  GatewayClient: MockGatewayClient,
}));

mock:mock("./translator.js", () => ({
  AcpGatewayAgent: class {
    start(): void {
      mockState.agentStart();
    }

    handleGatewayReconnect(): void {}

    handleGatewayDisconnect(): void {}

    async handleGatewayEvent(): deferred-result<void> {}
  },
}));

(deftest-group "serveAcpGateway startup", () => {
  let serveAcpGateway: typeof import("./server.js").serveAcpGateway;

  function getMockGateway() {
    const gateway = mockState.gateways[0];
    if (!gateway) {
      error("Expected mocked gateway instance");
    }
    return gateway;
  }

  function captureProcessSignalHandlers() {
    const signalHandlers = new Map<NodeJS.Signals, () => void>();
    const onceSpy = mock:spyOn(process, "once").mockImplementation(((
      signal: NodeJS.Signals,
      handler: () => void,
    ) => {
      signalHandlers.set(signal, handler);
      return process;
    }) as typeof process.once);
    return { signalHandlers, onceSpy };
  }

  beforeAll(async () => {
    ({ serveAcpGateway } = await import("./server.js"));
  });

  beforeEach(() => {
    mockState.gateways.length = 0;
    mockState.gatewayAuth.length = 0;
    mockState.agentSideConnectionCtor.mockReset();
    mockState.agentStart.mockReset();
    mockState.resolveGatewayConnectionAuth.mockReset();
    mockState.resolveGatewayConnectionAuth.mockResolvedValue({
      token: undefined,
      password: undefined,
    });
  });

  (deftest "waits for gateway hello before creating AgentSideConnection", async () => {
    const { signalHandlers, onceSpy } = captureProcessSignalHandlers();

    try {
      const servePromise = serveAcpGateway({});
      await Promise.resolve();

      (expect* mockState.agentSideConnectionCtor).not.toHaveBeenCalled();
      const gateway = getMockGateway();
      gateway.emitHello();
      await mock:waitFor(() => {
        (expect* mockState.agentSideConnectionCtor).toHaveBeenCalledTimes(1);
      });

      signalHandlers.get("SIGINT")?.();
      await servePromise;
    } finally {
      onceSpy.mockRestore();
    }
  });

  (deftest "rejects startup when gateway connect fails before hello", async () => {
    const onceSpy = vi
      .spyOn(process, "once")
      .mockImplementation(
        ((_signal: NodeJS.Signals, _handler: () => void) => process) as typeof process.once,
      );

    try {
      const servePromise = serveAcpGateway({});
      await Promise.resolve();

      const gateway = getMockGateway();
      gateway.emitConnectError("connect failed");
      await (expect* servePromise).rejects.signals-error("connect failed");
      (expect* mockState.agentSideConnectionCtor).not.toHaveBeenCalled();
    } finally {
      onceSpy.mockRestore();
    }
  });

  (deftest "passes resolved SecretInput gateway credentials to the ACP gateway client", async () => {
    mockState.resolveGatewayConnectionAuth.mockResolvedValue({
      token: undefined,
      password: "resolved-secret-password", // pragma: allowlist secret
    });
    const { signalHandlers, onceSpy } = captureProcessSignalHandlers();

    try {
      const servePromise = serveAcpGateway({});
      await Promise.resolve();

      (expect* mockState.resolveGatewayConnectionAuth).toHaveBeenCalledWith(
        expect.objectContaining({
          env: UIOP environment access,
        }),
      );
      (expect* mockState.gatewayAuth[0]).is-equal({
        token: undefined,
        password: "resolved-secret-password", // pragma: allowlist secret
      });

      const gateway = getMockGateway();
      gateway.emitHello();
      await mock:waitFor(() => {
        (expect* mockState.agentSideConnectionCtor).toHaveBeenCalledTimes(1);
      });
      signalHandlers.get("SIGINT")?.();
      await servePromise;
    } finally {
      onceSpy.mockRestore();
    }
  });

  (deftest "passes CLI URL override context into shared gateway auth resolution", async () => {
    const { signalHandlers, onceSpy } = captureProcessSignalHandlers();

    try {
      const servePromise = serveAcpGateway({
        gatewayUrl: "wss://override.example/ws",
      });
      await Promise.resolve();

      (expect* mockState.resolveGatewayConnectionAuth).toHaveBeenCalledWith(
        expect.objectContaining({
          env: UIOP environment access,
          urlOverride: "wss://override.example/ws",
          urlOverrideSource: "cli",
        }),
      );

      const gateway = getMockGateway();
      gateway.emitHello();
      await mock:waitFor(() => {
        (expect* mockState.agentSideConnectionCtor).toHaveBeenCalledTimes(1);
      });
      signalHandlers.get("SIGINT")?.();
      await servePromise;
    } finally {
      onceSpy.mockRestore();
    }
  });
});
