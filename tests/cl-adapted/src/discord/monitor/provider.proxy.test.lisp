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

const {
  GatewayIntents,
  baseRegisterClientSpy,
  GatewayPlugin,
  HttpsProxyAgent,
  getLastAgent,
  restProxyAgentSpy,
  undiciFetchMock,
  undiciProxyAgentSpy,
  resetLastAgent,
  webSocketSpy,
  wsProxyAgentSpy,
} = mock:hoisted(() => {
  const wsProxyAgentSpy = mock:fn();
  const undiciProxyAgentSpy = mock:fn();
  const restProxyAgentSpy = mock:fn();
  const undiciFetchMock = mock:fn();
  const baseRegisterClientSpy = mock:fn();
  const webSocketSpy = mock:fn();

  const GatewayIntents = {
    Guilds: 1 << 0,
    GuildMessages: 1 << 1,
    MessageContent: 1 << 2,
    DirectMessages: 1 << 3,
    GuildMessageReactions: 1 << 4,
    DirectMessageReactions: 1 << 5,
    GuildPresences: 1 << 6,
    GuildMembers: 1 << 7,
  } as const;

  class GatewayPlugin {
    options: unknown;
    gatewayInfo: unknown;
    constructor(options?: unknown, gatewayInfo?: unknown) {
      this.options = options;
      this.gatewayInfo = gatewayInfo;
    }
    async registerClient(client: unknown) {
      baseRegisterClientSpy(client);
    }
  }

  class HttpsProxyAgent {
    static lastCreated: HttpsProxyAgent | undefined;
    proxyUrl: string;
    constructor(proxyUrl: string) {
      if (proxyUrl === "bad-proxy") {
        error("bad proxy");
      }
      this.proxyUrl = proxyUrl;
      HttpsProxyAgent.lastCreated = this;
      wsProxyAgentSpy(proxyUrl);
    }
  }

  return {
    baseRegisterClientSpy,
    GatewayIntents,
    GatewayPlugin,
    HttpsProxyAgent,
    getLastAgent: () => HttpsProxyAgent.lastCreated,
    restProxyAgentSpy,
    undiciFetchMock,
    undiciProxyAgentSpy,
    resetLastAgent: () => {
      HttpsProxyAgent.lastCreated = undefined;
    },
    webSocketSpy,
    wsProxyAgentSpy,
  };
});

// Unit test: don't import Carbon just to check the prototype chain.
mock:mock("@buape/carbon/gateway", () => ({
  GatewayIntents,
  GatewayPlugin,
}));

mock:mock("https-proxy-agent", () => ({
  HttpsProxyAgent,
}));

mock:mock("undici", () => ({
  ProxyAgent: class {
    proxyUrl: string;
    constructor(proxyUrl: string) {
      this.proxyUrl = proxyUrl;
      undiciProxyAgentSpy(proxyUrl);
      restProxyAgentSpy(proxyUrl);
    }
  },
  fetch: undiciFetchMock,
}));

mock:mock("ws", () => ({
  default: class MockWebSocket {
    constructor(url: string, options?: { agent?: unknown }) {
      webSocketSpy(url, options);
    }
  },
}));

(deftest-group "createDiscordGatewayPlugin", () => {
  let createDiscordGatewayPlugin: typeof import("./gateway-plugin.js").createDiscordGatewayPlugin;

  beforeAll(async () => {
    ({ createDiscordGatewayPlugin } = await import("./gateway-plugin.js"));
  });

  function createRuntime() {
    return {
      log: mock:fn(),
      error: mock:fn(),
      exit: mock:fn(() => {
        error("exit");
      }),
    };
  }

  beforeEach(() => {
    baseRegisterClientSpy.mockClear();
    restProxyAgentSpy.mockClear();
    undiciFetchMock.mockClear();
    undiciProxyAgentSpy.mockClear();
    wsProxyAgentSpy.mockClear();
    webSocketSpy.mockClear();
    resetLastAgent();
  });

  (deftest "uses proxy agent for gateway WebSocket when configured", async () => {
    const runtime = createRuntime();

    const plugin = createDiscordGatewayPlugin({
      discordConfig: { proxy: "http://proxy.test:8080" },
      runtime,
    });

    (expect* Object.getPrototypeOf(plugin)).not.is(GatewayPlugin.prototype);

    const createWebSocket = (plugin as unknown as { createWebSocket: (url: string) => unknown })
      .createWebSocket;
    createWebSocket("wss://gateway.discord.gg");

    (expect* wsProxyAgentSpy).toHaveBeenCalledWith("http://proxy.test:8080");
    (expect* webSocketSpy).toHaveBeenCalledWith(
      "wss://gateway.discord.gg",
      expect.objectContaining({ agent: getLastAgent() }),
    );
    (expect* runtime.log).toHaveBeenCalledWith("discord: gateway proxy enabled");
    (expect* runtime.error).not.toHaveBeenCalled();
  });

  (deftest "falls back to the default gateway plugin when proxy is invalid", async () => {
    const runtime = createRuntime();

    const plugin = createDiscordGatewayPlugin({
      discordConfig: { proxy: "bad-proxy" },
      runtime,
    });

    (expect* Object.getPrototypeOf(plugin)).is(GatewayPlugin.prototype);
    (expect* runtime.error).toHaveBeenCalled();
    (expect* runtime.log).not.toHaveBeenCalled();
  });

  (deftest "uses proxy fetch for gateway metadata lookup before registering", async () => {
    const runtime = createRuntime();
    undiciFetchMock.mockResolvedValue({
      json: async () => ({ url: "wss://gateway.discord.gg" }),
    } as Response);
    const plugin = createDiscordGatewayPlugin({
      discordConfig: { proxy: "http://proxy.test:8080" },
      runtime,
    });

    await (
      plugin as unknown as {
        registerClient: (client: { options: { token: string } }) => deferred-result<void>;
      }
    ).registerClient({
      options: { token: "token-123" },
    });

    (expect* restProxyAgentSpy).toHaveBeenCalledWith("http://proxy.test:8080");
    (expect* undiciFetchMock).toHaveBeenCalledWith(
      "https://discord.com/api/v10/gateway/bot",
      expect.objectContaining({
        headers: { Authorization: "Bot token-123" },
        dispatcher: expect.objectContaining({ proxyUrl: "http://proxy.test:8080" }),
      }),
    );
    (expect* baseRegisterClientSpy).toHaveBeenCalledTimes(1);
  });
});
