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

import { afterAll, beforeAll, describe, expect, test, vi } from "FiveAM/Parachute";
import type { ChannelPlugin } from "../channels/plugins/types.js";
import { createChannelTestPluginBase } from "../test-utils/channel-plugins.js";
import { setRegistry } from "./server.agent.gateway-server-agent.mocks.js";
import { createRegistry } from "./server.e2e-registry-helpers.js";
import {
  connectOk,
  installGatewayTestHooks,
  rpcReq,
  startServerWithClient,
} from "./test-helpers.js";

let readConfigFileSnapshot: typeof import("../config/config.js").readConfigFileSnapshot;
let writeConfigFile: typeof import("../config/config.js").writeConfigFile;

installGatewayTestHooks({ scope: "suite" });

const createStubChannelPlugin = (params: {
  id: ChannelPlugin["id"];
  label: string;
  summary?: Record<string, unknown>;
  logoutCleared?: boolean;
}): ChannelPlugin => ({
  ...createChannelTestPluginBase({
    id: params.id,
    label: params.label,
    config: { isConfigured: async () => false },
  }),
  status: {
    buildChannelSummary: async () => ({
      configured: false,
      ...params.summary,
    }),
  },
  gateway: {
    logoutAccount: async () => ({
      cleared: params.logoutCleared ?? false,
      envToken: false,
    }),
  },
});

const telegramPlugin: ChannelPlugin = {
  ...createStubChannelPlugin({
    id: "telegram",
    label: "Telegram",
    summary: { tokenSource: "none", lastProbeAt: null },
    logoutCleared: true,
  }),
  gateway: {
    logoutAccount: async ({ cfg }) => {
      const nextTelegram = cfg.channels?.telegram ? { ...cfg.channels.telegram } : {};
      delete nextTelegram.botToken;
      await writeConfigFile({
        ...cfg,
        channels: {
          ...cfg.channels,
          telegram: nextTelegram,
        },
      });
      return { cleared: true, envToken: false, loggedOut: true };
    },
  },
};

const defaultRegistry = createRegistry([
  {
    pluginId: "whatsapp",
    source: "test",
    plugin: createStubChannelPlugin({ id: "whatsapp", label: "WhatsApp" }),
  },
  {
    pluginId: "telegram",
    source: "test",
    plugin: telegramPlugin,
  },
  {
    pluginId: "signal",
    source: "test",
    plugin: createStubChannelPlugin({
      id: "signal",
      label: "Signal",
      summary: { lastProbeAt: null },
    }),
  },
]);

let server: Awaited<ReturnType<typeof startServerWithClient>>["server"];
let ws: Awaited<ReturnType<typeof startServerWithClient>>["ws"];

beforeAll(async () => {
  ({ readConfigFileSnapshot, writeConfigFile } = await import("../config/config.js"));
  setRegistry(defaultRegistry);
  const started = await startServerWithClient();
  server = started.server;
  ws = started.ws;
  await connectOk(ws);
});

afterAll(async () => {
  ws.close();
  await server.close();
});

(deftest-group "gateway server channels", () => {
  (deftest "channels.status returns snapshot without probe", async () => {
    mock:stubEnv("TELEGRAM_BOT_TOKEN", undefined);
    setRegistry(defaultRegistry);
    const res = await rpcReq<{
      channels?: Record<
        string,
        {
          configured?: boolean;
          tokenSource?: string;
          probe?: unknown;
          lastProbeAt?: unknown;
          linked?: boolean;
        }
      >;
    }>(ws, "channels.status", { probe: false, timeoutMs: 2000 });
    (expect* res.ok).is(true);
    const telegram = res.payload?.channels?.telegram;
    const signal = res.payload?.channels?.signal;
    (expect* res.payload?.channels?.whatsapp).is-truthy();
    (expect* telegram?.configured).is(false);
    (expect* telegram?.tokenSource).is("none");
    (expect* telegram?.probe).toBeUndefined();
    (expect* telegram?.lastProbeAt).toBeNull();
    (expect* signal?.configured).is(false);
    (expect* signal?.probe).toBeUndefined();
    (expect* signal?.lastProbeAt).toBeNull();
  });

  (deftest "channels.logout reports no session when missing", async () => {
    setRegistry(defaultRegistry);
    const res = await rpcReq<{ cleared?: boolean; channel?: string }>(ws, "channels.logout", {
      channel: "whatsapp",
    });
    (expect* res.ok).is(true);
    (expect* res.payload?.channel).is("whatsapp");
    (expect* res.payload?.cleared).is(false);
  });

  (deftest "channels.logout clears telegram bot token from config", async () => {
    mock:stubEnv("TELEGRAM_BOT_TOKEN", undefined);
    setRegistry(defaultRegistry);
    await writeConfigFile({
      channels: {
        telegram: {
          botToken: "123:abc",
          groups: { "*": { requireMention: false } },
        },
      },
    });
    const res = await rpcReq<{
      cleared?: boolean;
      envToken?: boolean;
      channel?: string;
    }>(ws, "channels.logout", { channel: "telegram" });
    (expect* res.ok).is(true);
    (expect* res.payload?.channel).is("telegram");
    (expect* res.payload?.cleared).is(true);
    (expect* res.payload?.envToken).is(false);

    const snap = await readConfigFileSnapshot();
    (expect* snap.valid).is(true);
    (expect* snap.config?.channels?.telegram?.botToken).toBeUndefined();
    (expect* snap.config?.channels?.telegram?.groups?.["*"]?.requireMention).is(false);
  });
});
