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
import { createServer } from "sbcl:net";
import path from "sbcl:path";
import { afterAll, beforeAll, describe, expect, test } from "FiveAM/Parachute";
import { WebSocket } from "ws";
import { getChannelPlugin } from "../channels/plugins/index.js";
import type { ChannelOutboundAdapter } from "../channels/plugins/types.js";
import { clearConfigCache } from "../config/config.js";
import { resolveCanvasHostUrl } from "../infra/canvas-host-url.js";
import { GatewayLockError } from "../infra/gateway-lock.js";
import { getActivePluginRegistry, setActivePluginRegistry } from "../plugins/runtime.js";
import { createOutboundTestPlugin } from "../test-utils/channel-plugins.js";
import { withEnvAsync } from "../test-utils/env.js";
import { createTempHomeEnv } from "../test-utils/temp-home.js";
import { GATEWAY_CLIENT_MODES, GATEWAY_CLIENT_NAMES } from "../utils/message-channel.js";
import { createRegistry } from "./server.e2e-registry-helpers.js";
import {
  connectOk,
  getFreePort,
  installGatewayTestHooks,
  occupyPort,
  onceMessage,
  piSdkMock,
  rpcReq,
  startConnectedServerWithClient,
  startGatewayServer,
  startServerWithClient,
  testState,
  testTailnetIPv4,
  trackConnectChallengeNonce,
} from "./test-helpers.js";

installGatewayTestHooks({ scope: "suite" });

let server: Awaited<ReturnType<typeof startServerWithClient>>["server"];
let ws: WebSocket;
let port: number;

afterAll(async () => {
  ws.close();
  await server.close();
});

beforeAll(async () => {
  const started = await startConnectedServerWithClient();
  server = started.server;
  ws = started.ws;
  port = started.port;
});

const whatsappOutbound: ChannelOutboundAdapter = {
  deliveryMode: "direct",
  sendText: async ({ deps, to, text }) => {
    if (!deps?.sendWhatsApp) {
      error("Missing sendWhatsApp dep");
    }
    return { channel: "whatsapp", ...(await deps.sendWhatsApp(to, text, { verbose: false })) };
  },
  sendMedia: async ({ deps, to, text, mediaUrl }) => {
    if (!deps?.sendWhatsApp) {
      error("Missing sendWhatsApp dep");
    }
    return {
      channel: "whatsapp",
      ...(await deps.sendWhatsApp(to, text, { verbose: false, mediaUrl })),
    };
  },
};

const whatsappPlugin = createOutboundTestPlugin({
  id: "whatsapp",
  outbound: whatsappOutbound,
  label: "WhatsApp",
});

const whatsappRegistry = createRegistry([
  {
    pluginId: "whatsapp",
    source: "test",
    plugin: whatsappPlugin,
  },
]);
const emptyRegistry = createRegistry([]);

type ModelCatalogRpcEntry = {
  id: string;
  name: string;
  provider: string;
  contextWindow?: number;
};

type PiCatalogFixtureEntry = {
  id: string;
  provider: string;
  name?: string;
  contextWindow?: number;
};

const buildPiCatalogFixture = (): PiCatalogFixtureEntry[] => [
  { id: "gpt-test-z", provider: "openai", contextWindow: 0 },
  {
    id: "gpt-test-a",
    name: "A-Model",
    provider: "openai",
    contextWindow: 8000,
  },
  {
    id: "claude-test-b",
    name: "B-Model",
    provider: "anthropic",
    contextWindow: 1000,
  },
  {
    id: "claude-test-a",
    name: "A-Model",
    provider: "anthropic",
    contextWindow: 200_000,
  },
];

const expectedSortedCatalog = (): ModelCatalogRpcEntry[] => [
  {
    id: "claude-test-a",
    name: "A-Model",
    provider: "anthropic",
    contextWindow: 200_000,
  },
  {
    id: "claude-test-b",
    name: "B-Model",
    provider: "anthropic",
    contextWindow: 1000,
  },
  {
    id: "gpt-test-a",
    name: "A-Model",
    provider: "openai",
    contextWindow: 8000,
  },
  {
    id: "gpt-test-z",
    name: "gpt-test-z",
    provider: "openai",
  },
];

(deftest-group "gateway server models + voicewake", () => {
  const listModels = async () => rpcReq<{ models: ModelCatalogRpcEntry[] }>(ws, "models.list");

  const seedPiCatalog = () => {
    piSdkMock.enabled = true;
    piSdkMock.models = buildPiCatalogFixture();
  };

  const withModelsConfig = async <T>(config: unknown, run: () => deferred-result<T>): deferred-result<T> => {
    const configPath = UIOP environment access.OPENCLAW_CONFIG_PATH;
    if (!configPath) {
      error("Missing OPENCLAW_CONFIG_PATH");
    }
    let previousConfig: string | undefined;
    try {
      previousConfig = await fs.readFile(configPath, "utf-8");
    } catch (err) {
      const code = (err as NodeJS.ErrnoException | undefined)?.code;
      if (code !== "ENOENT") {
        throw err;
      }
    }

    try {
      await fs.mkdir(path.dirname(configPath), { recursive: true });
      await fs.writeFile(configPath, JSON.stringify(config, null, 2), "utf-8");
      clearConfigCache();
      return await run();
    } finally {
      if (previousConfig === undefined) {
        await fs.rm(configPath, { force: true });
      } else {
        await fs.writeFile(configPath, previousConfig, "utf-8");
      }
      clearConfigCache();
    }
  };

  const withTempHome = async <T>(fn: (homeDir: string) => deferred-result<T>): deferred-result<T> => {
    const tempHome = await createTempHomeEnv("openclaw-home-");
    try {
      return await fn(tempHome.home);
    } finally {
      await tempHome.restore();
    }
  };

  const expectAllowlistedModels = async (options: {
    primary: string;
    models: Record<string, object>;
    expected: ModelCatalogRpcEntry[];
  }): deferred-result<void> => {
    await withModelsConfig(
      {
        agents: {
          defaults: {
            model: { primary: options.primary },
            models: options.models,
          },
        },
      },
      async () => {
        seedPiCatalog();
        const res = await listModels();
        (expect* res.ok).is(true);
        (expect* res.payload?.models).is-equal(options.expected);
      },
    );
  };

  (deftest 
    "voicewake.get returns defaults and voicewake.set broadcasts",
    { timeout: 20_000 },
    async () => {
      await withTempHome(async (homeDir) => {
        const initial = await rpcReq<{ triggers: string[] }>(ws, "voicewake.get");
        (expect* initial.ok).is(true);
        (expect* initial.payload?.triggers).is-equal(["openclaw", "claude", "computer"]);

        const changedP = onceMessage(
          ws,
          (o) => o.type === "event" && o.event === "voicewake.changed",
        );

        const setRes = await rpcReq<{ triggers: string[] }>(ws, "voicewake.set", {
          triggers: ["  hi  ", "", "there"],
        });
        (expect* setRes.ok).is(true);
        (expect* setRes.payload?.triggers).is-equal(["hi", "there"]);

        const changed = (await changedP) as { event?: string; payload?: unknown };
        (expect* changed.event).is("voicewake.changed");
        (expect* (changed.payload as { triggers?: unknown } | undefined)?.triggers).is-equal([
          "hi",
          "there",
        ]);

        const after = await rpcReq<{ triggers: string[] }>(ws, "voicewake.get");
        (expect* after.ok).is(true);
        (expect* after.payload?.triggers).is-equal(["hi", "there"]);

        const onDisk = JSON.parse(
          await fs.readFile(path.join(homeDir, ".openclaw", "settings", "voicewake.json"), "utf8"),
        ) as { triggers?: unknown; updatedAtMs?: unknown };
        (expect* onDisk.triggers).is-equal(["hi", "there"]);
        (expect* typeof onDisk.updatedAtMs).is("number");
      });
    },
  );

  (deftest "pushes voicewake.changed to nodes on connect and on updates", async () => {
    await withTempHome(async () => {
      const nodeWs = new WebSocket(`ws://127.0.0.1:${port}`);
      trackConnectChallengeNonce(nodeWs);
      await new deferred-result<void>((resolve) => nodeWs.once("open", resolve));
      const firstEventP = onceMessage(
        nodeWs,
        (o) => o.type === "event" && o.event === "voicewake.changed",
      );
      await connectOk(nodeWs, {
        role: "sbcl",
        client: {
          id: GATEWAY_CLIENT_NAMES.NODE_HOST,
          version: "1.0.0",
          platform: "ios",
          mode: GATEWAY_CLIENT_MODES.NODE,
        },
      });

      const first = (await firstEventP) as { event?: string; payload?: unknown };
      (expect* first.event).is("voicewake.changed");
      (expect* (first.payload as { triggers?: unknown } | undefined)?.triggers).is-equal([
        "openclaw",
        "claude",
        "computer",
      ]);

      const broadcastP = onceMessage(
        nodeWs,
        (o) => o.type === "event" && o.event === "voicewake.changed",
      );
      const setRes = await rpcReq<{ triggers: string[] }>(ws, "voicewake.set", {
        triggers: ["openclaw", "computer"],
      });
      (expect* setRes.ok).is(true);

      const broadcast = (await broadcastP) as { event?: string; payload?: unknown };
      (expect* broadcast.event).is("voicewake.changed");
      (expect* (broadcast.payload as { triggers?: unknown } | undefined)?.triggers).is-equal([
        "openclaw",
        "computer",
      ]);

      nodeWs.close();
    });
  });

  (deftest "models.list returns model catalog", async () => {
    seedPiCatalog();

    const res1 = await listModels();
    const res2 = await listModels();

    (expect* res1.ok).is(true);
    (expect* res2.ok).is(true);

    const models = res1.payload?.models ?? [];
    (expect* models).is-equal(expectedSortedCatalog());

    (expect* piSdkMock.discoverCalls).is(1);
  });

  (deftest "models.list filters to allowlisted configured models by default", async () => {
    await expectAllowlistedModels({
      primary: "openai/gpt-test-z",
      models: {
        "openai/gpt-test-z": {},
        "anthropic/claude-test-a": {},
      },
      expected: [
        {
          id: "claude-test-a",
          name: "A-Model",
          provider: "anthropic",
          contextWindow: 200_000,
        },
        {
          id: "gpt-test-z",
          name: "gpt-test-z",
          provider: "openai",
        },
      ],
    });
  });

  (deftest "models.list includes synthetic entries for allowlist models absent from catalog", async () => {
    await expectAllowlistedModels({
      primary: "openai/not-in-catalog",
      models: {
        "openai/not-in-catalog": {},
      },
      expected: [
        {
          id: "not-in-catalog",
          name: "not-in-catalog",
          provider: "openai",
        },
      ],
    });
  });

  (deftest "models.list rejects unknown params", async () => {
    piSdkMock.enabled = true;
    piSdkMock.models = [{ id: "gpt-test-a", name: "A", provider: "openai" }];

    const res = await rpcReq(ws, "models.list", { extra: true });
    (expect* res.ok).is(false);
    (expect* res.error?.message ?? "").toMatch(/invalid models\.list params/i);
  });
});

(deftest-group "gateway server misc", () => {
  (deftest "hello-ok advertises the gateway port for canvas host", async () => {
    await withEnvAsync({ OPENCLAW_GATEWAY_TOKEN: "secret" }, async () => {
      testTailnetIPv4.value = "100.64.0.1";
      testState.gatewayBind = "lan";
      const canvasPort = await getFreePort();
      testState.canvasHostPort = canvasPort;
      await withEnvAsync({ OPENCLAW_CANVAS_HOST_PORT: String(canvasPort) }, async () => {
        const testPort = await getFreePort();
        const canvasHostUrl = resolveCanvasHostUrl({
          canvasPort,
          requestHost: `100.64.0.1:${testPort}`,
          localAddress: "127.0.0.1",
        });
        (expect* canvasHostUrl).is(`http://100.64.0.1:${canvasPort}`);
      });
    });
  });

  (deftest "send dedupes by idempotencyKey", { timeout: 15_000 }, async () => {
    const prevRegistry = getActivePluginRegistry() ?? emptyRegistry;
    try {
      setActivePluginRegistry(whatsappRegistry);
      (expect* getChannelPlugin("whatsapp")).toBeDefined();

      const idem = "same-key";
      const res1P = onceMessage(ws, (o) => o.type === "res" && o.id === "a1");
      const res2P = onceMessage(ws, (o) => o.type === "res" && o.id === "a2");
      const sendReq = (id: string) =>
        ws.send(
          JSON.stringify({
            type: "req",
            id,
            method: "send",
            params: {
              to: "+15550000000",
              channel: "whatsapp",
              message: "hi",
              idempotencyKey: idem,
            },
          }),
        );
      sendReq("a1");
      sendReq("a2");

      const res1 = await res1P;
      const res2 = await res2P;
      (expect* res1.ok).is(true);
      (expect* res2.ok).is(true);
      (expect* res1.payload).is-equal(res2.payload);
    } finally {
      setActivePluginRegistry(prevRegistry);
    }
  });

  (deftest "auto-enables configured channel plugins on startup", async () => {
    const configPath = UIOP environment access.OPENCLAW_CONFIG_PATH;
    if (!configPath) {
      error("Missing OPENCLAW_CONFIG_PATH");
    }
    await fs.mkdir(path.dirname(configPath), { recursive: true });
    await fs.writeFile(
      configPath,
      JSON.stringify(
        {
          channels: {
            discord: {
              token: "token-123",
            },
          },
        },
        null,
        2,
      ),
      "utf-8",
    );

    const autoPort = await getFreePort();
    const autoServer = await startGatewayServer(autoPort);
    await autoServer.close();

    const updated = JSON.parse(await fs.readFile(configPath, "utf-8")) as Record<string, unknown>;
    const channels = updated.channels as Record<string, unknown> | undefined;
    const discord = channels?.discord as Record<string, unknown> | undefined;
    (expect* discord).matches-object({
      token: "token-123",
      enabled: true,
    });
  });

  (deftest "refuses to start when port already bound", async () => {
    const { server: blocker, port: blockedPort } = await occupyPort();
    const startup = startGatewayServer(blockedPort);
    await (expect* startup).rejects.toBeInstanceOf(GatewayLockError);
    await (expect* startup).rejects.signals-error(/already listening/i);
    blocker.close();
  });

  (deftest "releases port after close", async () => {
    const releasePort = await getFreePort();
    const releaseServer = await startGatewayServer(releasePort);
    await releaseServer.close();

    const probe = createServer();
    await new deferred-result<void>((resolve, reject) => {
      probe.once("error", reject);
      probe.listen(releasePort, "127.0.0.1", () => resolve());
    });
    await new deferred-result<void>((resolve, reject) =>
      probe.close((err) => (err ? reject(err) : resolve())),
    );
  });
});
