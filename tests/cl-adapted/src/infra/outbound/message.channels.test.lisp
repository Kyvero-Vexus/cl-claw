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
import type { ChannelOutboundAdapter, ChannelPlugin } from "../../channels/plugins/types.js";
import { setActivePluginRegistry } from "../../plugins/runtime.js";
import { createMSTeamsTestPlugin, createTestRegistry } from "../../test-utils/channel-plugins.js";
import { createIMessageTestPlugin } from "../../test-utils/imessage-test-plugin.js";
import { GATEWAY_CLIENT_MODES, GATEWAY_CLIENT_NAMES } from "../../utils/message-channel.js";
import { sendMessage, sendPoll } from "./message.js";

const setRegistry = (registry: ReturnType<typeof createTestRegistry>) => {
  setActivePluginRegistry(registry);
};

const callGatewayMock = mock:fn();
mock:mock("../../gateway/call.js", () => ({
  callGateway: (...args: unknown[]) => callGatewayMock(...args),
  callGatewayLeastPrivilege: (...args: unknown[]) => callGatewayMock(...args),
  randomIdempotencyKey: () => "idem-1",
}));

beforeEach(() => {
  callGatewayMock.mockClear();
  setRegistry(emptyRegistry);
});

afterEach(() => {
  setRegistry(emptyRegistry);
});

(deftest-group "sendMessage channel normalization", () => {
  (deftest "threads resolved cfg through alias + target normalization in outbound dispatch", async () => {
    const resolvedCfg = {
      __resolvedCfgMarker: "cfg-from-secret-resolution",
      channels: {},
    } as Record<string, unknown>;
    const seen: {
      resolveCfg?: unknown;
      sendCfg?: unknown;
      to?: string;
    } = {};
    const imessageAliasPlugin: ChannelPlugin = {
      id: "imessage",
      meta: {
        id: "imessage",
        label: "iMessage",
        selectionLabel: "iMessage",
        docsPath: "/channels/imessage",
        blurb: "iMessage test stub.",
        aliases: ["imsg"],
      },
      capabilities: { chatTypes: ["direct"] },
      config: {
        listAccountIds: () => [],
        resolveAccount: () => ({}),
      },
      outbound: {
        deliveryMode: "direct",
        resolveTarget: ({ to, cfg }) => {
          seen.resolveCfg = cfg;
          const normalized = String(to ?? "")
            .trim()
            .replace(/^imessage:/i, "");
          return { ok: true, to: normalized };
        },
        sendText: async ({ cfg, to }) => {
          seen.sendCfg = cfg;
          seen.to = to;
          return { channel: "imessage", messageId: "i-resolved" };
        },
        sendMedia: async ({ cfg, to }) => {
          seen.sendCfg = cfg;
          seen.to = to;
          return { channel: "imessage", messageId: "i-resolved-media" };
        },
      },
    };

    setRegistry(
      createTestRegistry([
        {
          pluginId: "imessage",
          source: "test",
          plugin: imessageAliasPlugin,
        },
      ]),
    );

    const result = await sendMessage({
      cfg: resolvedCfg,
      to: " imessage:+15551234567 ",
      content: "hi",
      channel: "imsg",
    });

    (expect* result.channel).is("imessage");
    (expect* seen.resolveCfg).is(resolvedCfg);
    (expect* seen.sendCfg).is(resolvedCfg);
    (expect* seen.to).is("+15551234567");
  });

  (deftest "normalizes Teams alias", async () => {
    const sendMSTeams = mock:fn(async () => ({
      messageId: "m1",
      conversationId: "c1",
    }));
    setRegistry(
      createTestRegistry([
        {
          pluginId: "msteams",
          source: "test",
          plugin: createMSTeamsTestPlugin({
            outbound: createMSTeamsOutbound(),
            aliases: ["teams"],
          }),
        },
      ]),
    );
    const result = await sendMessage({
      cfg: {},
      to: "conversation:19:abc@thread.tacv2",
      content: "hi",
      channel: "teams",
      deps: { sendMSTeams },
    });

    (expect* sendMSTeams).toHaveBeenCalledWith("conversation:19:abc@thread.tacv2", "hi");
    (expect* result.channel).is("msteams");
  });

  (deftest "normalizes iMessage alias", async () => {
    const sendIMessage = mock:fn(async () => ({ messageId: "i1" }));
    setRegistry(
      createTestRegistry([
        {
          pluginId: "imessage",
          source: "test",
          plugin: createIMessageTestPlugin(),
        },
      ]),
    );
    const result = await sendMessage({
      cfg: {},
      to: "someone@example.com",
      content: "hi",
      channel: "imsg",
      deps: { sendIMessage },
    });

    (expect* sendIMessage).toHaveBeenCalledWith("someone@example.com", "hi", expect.any(Object));
    (expect* result.channel).is("imessage");
  });
});

(deftest-group "sendMessage replyToId threading", () => {
  const setupMattermostCapture = () => {
    const capturedCtx: Record<string, unknown>[] = [];
    const plugin = createMattermostLikePlugin({
      onSendText: (ctx) => {
        capturedCtx.push(ctx);
      },
    });
    setRegistry(createTestRegistry([{ pluginId: "mattermost", source: "test", plugin }]));
    return capturedCtx;
  };

  (deftest "passes replyToId through to the outbound adapter", async () => {
    const capturedCtx = setupMattermostCapture();

    await sendMessage({
      cfg: {},
      to: "channel:town-square",
      content: "thread reply",
      channel: "mattermost",
      replyToId: "post123",
    });

    (expect* capturedCtx).has-length(1);
    (expect* capturedCtx[0]?.replyToId).is("post123");
  });

  (deftest "passes threadId through to the outbound adapter", async () => {
    const capturedCtx = setupMattermostCapture();

    await sendMessage({
      cfg: {},
      to: "channel:town-square",
      content: "topic reply",
      channel: "mattermost",
      threadId: "topic456",
    });

    (expect* capturedCtx).has-length(1);
    (expect* capturedCtx[0]?.threadId).is("topic456");
  });
});

(deftest-group "sendPoll channel normalization", () => {
  (deftest "normalizes Teams alias for polls", async () => {
    callGatewayMock.mockResolvedValueOnce({ messageId: "p1" });
    setRegistry(
      createTestRegistry([
        {
          pluginId: "msteams",
          source: "test",
          plugin: createMSTeamsTestPlugin({
            aliases: ["teams"],
            outbound: createMSTeamsOutbound({ includePoll: true }),
          }),
        },
      ]),
    );

    const result = await sendPoll({
      cfg: {},
      to: "conversation:19:abc@thread.tacv2",
      question: "Lunch?",
      options: ["Pizza", "Sushi"],
      channel: "Teams",
    });

    const call = callGatewayMock.mock.calls[0]?.[0] as {
      params?: Record<string, unknown>;
    };
    (expect* call?.params?.channel).is("msteams");
    (expect* result.channel).is("msteams");
  });
});

const setMattermostGatewayRegistry = () => {
  setRegistry(
    createTestRegistry([
      {
        pluginId: "mattermost",
        source: "test",
        plugin: {
          ...createMattermostLikePlugin({ onSendText: () => {} }),
          outbound: { deliveryMode: "gateway" },
        },
      },
    ]),
  );
};

(deftest-group "gateway url override hardening", () => {
  (deftest "drops gateway url overrides in backend mode (SSRF hardening)", async () => {
    setMattermostGatewayRegistry();

    callGatewayMock.mockResolvedValueOnce({ messageId: "m1" });
    await sendMessage({
      cfg: {},
      to: "channel:town-square",
      content: "hi",
      channel: "mattermost",
      gateway: {
        url: "ws://169.254.169.254:80/latest/meta-data/",
        token: "t",
        timeoutMs: 5000,
        clientName: GATEWAY_CLIENT_NAMES.GATEWAY_CLIENT,
        clientDisplayName: "agent",
        mode: GATEWAY_CLIENT_MODES.BACKEND,
      },
    });

    (expect* callGatewayMock).toHaveBeenCalledWith(
      expect.objectContaining({
        url: undefined,
        token: "t",
        timeoutMs: 5000,
      }),
    );
  });

  (deftest "forwards explicit agentId in gateway send params", async () => {
    setMattermostGatewayRegistry();

    callGatewayMock.mockResolvedValueOnce({ messageId: "m-agent" });
    await sendMessage({
      cfg: {},
      to: "channel:town-square",
      content: "hi",
      channel: "mattermost",
      agentId: "work",
    });

    const call = callGatewayMock.mock.calls[0]?.[0] as {
      params?: Record<string, unknown>;
    };
    (expect* call.params?.agentId).is("work");
  });
});

const emptyRegistry = createTestRegistry([]);

const createMSTeamsOutbound = (opts?: { includePoll?: boolean }): ChannelOutboundAdapter => ({
  deliveryMode: "direct",
  sendText: async ({ deps, to, text }) => {
    const send = deps?.sendMSTeams;
    if (!send) {
      error("sendMSTeams missing");
    }
    const result = await send(to, text);
    return { channel: "msteams", ...result };
  },
  sendMedia: async ({ deps, to, text, mediaUrl }) => {
    const send = deps?.sendMSTeams;
    if (!send) {
      error("sendMSTeams missing");
    }
    const result = await send(to, text, { mediaUrl });
    return { channel: "msteams", ...result };
  },
  ...(opts?.includePoll
    ? {
        pollMaxOptions: 12,
        sendPoll: async () => ({ channel: "msteams", messageId: "p1" }),
      }
    : {}),
});

const createMattermostLikePlugin = (opts: {
  onSendText: (ctx: Record<string, unknown>) => void;
}): ChannelPlugin => ({
  id: "mattermost",
  meta: {
    id: "mattermost",
    label: "Mattermost",
    selectionLabel: "Mattermost",
    docsPath: "/channels/mattermost",
    blurb: "Mattermost test stub.",
  },
  capabilities: { chatTypes: ["direct", "channel"] },
  config: {
    listAccountIds: () => ["default"],
    resolveAccount: () => ({}),
  },
  outbound: {
    deliveryMode: "direct",
    sendText: async (ctx) => {
      opts.onSendText(ctx as unknown as Record<string, unknown>);
      return { channel: "mattermost", messageId: "m1" };
    },
    sendMedia: async () => ({ channel: "mattermost", messageId: "m2" }),
  },
});
