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

import type {
  ButtonInteraction,
  ComponentData,
  ModalInteraction,
  StringSelectMenuInteraction,
} from "@buape/carbon";
import type { Client } from "@buape/carbon";
import type { GatewayPresenceUpdate } from "discord-api-types/v10";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";
import type { DiscordAccountConfig } from "../../config/types.discord.js";
import { buildAgentSessionKey } from "../../routing/resolve-route.js";
import {
  clearDiscordComponentEntries,
  registerDiscordComponentEntries,
  resolveDiscordComponentEntry,
  resolveDiscordModalEntry,
} from "../components-registry.js";
import type { DiscordComponentEntry, DiscordModalEntry } from "../components.js";
import {
  createAgentComponentButton,
  createAgentSelectMenu,
  createDiscordComponentButton,
  createDiscordComponentModal,
} from "./agent-components.js";
import type { DiscordChannelConfigResolved } from "./allow-list.js";
import {
  resolveDiscordMemberAllowed,
  resolveDiscordOwnerAllowFrom,
  resolveDiscordRoleAllowed,
} from "./allow-list.js";
import {
  clearGateways,
  getGateway,
  registerGateway,
  unregisterGateway,
} from "./gateway-registry.js";
import { clearPresences, getPresence, presenceCacheSize, setPresence } from "./presence-cache.js";
import { resolveDiscordPresenceUpdate } from "./presence.js";
import {
  maybeCreateDiscordAutoThread,
  resolveDiscordAutoThreadContext,
  resolveDiscordAutoThreadReplyPlan,
  resolveDiscordReplyDeliveryPlan,
} from "./threading.js";

const readAllowFromStoreMock = mock:hoisted(() => mock:fn());
const upsertPairingRequestMock = mock:hoisted(() => mock:fn());
const enqueueSystemEventMock = mock:hoisted(() => mock:fn());
const dispatchReplyMock = mock:hoisted(() => mock:fn());
const deliverDiscordReplyMock = mock:hoisted(() => mock:fn());
const recordInboundSessionMock = mock:hoisted(() => mock:fn());
const readSessionUpdatedAtMock = mock:hoisted(() => mock:fn());
const resolveStorePathMock = mock:hoisted(() => mock:fn());
let lastDispatchCtx: Record<string, unknown> | undefined;

mock:mock("../../pairing/pairing-store.js", () => ({
  readChannelAllowFromStore: (...args: unknown[]) => readAllowFromStoreMock(...args),
  upsertChannelPairingRequest: (...args: unknown[]) => upsertPairingRequestMock(...args),
}));

mock:mock("../../infra/system-events.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../infra/system-events.js")>();
  return {
    ...actual,
    enqueueSystemEvent: (...args: unknown[]) => enqueueSystemEventMock(...args),
  };
});

mock:mock("../../auto-reply/reply/provider-dispatcher.js", () => ({
  dispatchReplyWithBufferedBlockDispatcher: (...args: unknown[]) => dispatchReplyMock(...args),
}));

mock:mock("./reply-delivery.js", () => ({
  deliverDiscordReply: (...args: unknown[]) => deliverDiscordReplyMock(...args),
}));

mock:mock("../../channels/session.js", () => ({
  recordInboundSession: (...args: unknown[]) => recordInboundSessionMock(...args),
}));

mock:mock("../../config/sessions.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../config/sessions.js")>();
  return {
    ...actual,
    readSessionUpdatedAt: (...args: unknown[]) => readSessionUpdatedAtMock(...args),
    resolveStorePath: (...args: unknown[]) => resolveStorePathMock(...args),
  };
});

(deftest-group "agent components", () => {
  const createCfg = (): OpenClawConfig => ({}) as OpenClawConfig;

  const createBaseDmInteraction = (overrides: Record<string, unknown> = {}) => {
    const reply = mock:fn().mockResolvedValue(undefined);
    const defer = mock:fn().mockResolvedValue(undefined);
    const interaction = {
      rawData: { channel_id: "dm-channel" },
      user: { id: "123456789", username: "Alice", discriminator: "1234" },
      defer,
      reply,
      ...overrides,
    };
    return { interaction, defer, reply };
  };

  const createDmButtonInteraction = (overrides: Partial<ButtonInteraction> = {}) => {
    const { interaction, defer, reply } = createBaseDmInteraction(
      overrides as Record<string, unknown>,
    );
    return {
      interaction: interaction as unknown as ButtonInteraction,
      defer,
      reply,
    };
  };

  const createDmSelectInteraction = (overrides: Partial<StringSelectMenuInteraction> = {}) => {
    const { interaction, defer, reply } = createBaseDmInteraction({
      values: ["alpha"],
      ...(overrides as Record<string, unknown>),
    });
    return {
      interaction: interaction as unknown as StringSelectMenuInteraction,
      defer,
      reply,
    };
  };

  beforeEach(() => {
    readAllowFromStoreMock.mockClear().mockResolvedValue([]);
    upsertPairingRequestMock.mockClear().mockResolvedValue({ code: "PAIRCODE", created: true });
    enqueueSystemEventMock.mockClear();
  });

  (deftest "sends pairing reply when DM sender is not allowlisted", async () => {
    const button = createAgentComponentButton({
      cfg: createCfg(),
      accountId: "default",
      dmPolicy: "pairing",
    });
    const { interaction, defer, reply } = createDmButtonInteraction();

    await button.run(interaction, { componentId: "hello" } as ComponentData);

    (expect* defer).toHaveBeenCalledWith({ ephemeral: true });
    (expect* reply).toHaveBeenCalledTimes(1);
    (expect* reply.mock.calls[0]?.[0]?.content).contains("Pairing code: PAIRCODE");
    (expect* enqueueSystemEventMock).not.toHaveBeenCalled();
  });

  (deftest "blocks DM interactions when only pairing store entries match in allowlist mode", async () => {
    readAllowFromStoreMock.mockResolvedValue(["123456789"]);
    const button = createAgentComponentButton({
      cfg: createCfg(),
      accountId: "default",
      dmPolicy: "allowlist",
    });
    const { interaction, defer, reply } = createDmButtonInteraction();

    await button.run(interaction, { componentId: "hello" } as ComponentData);

    (expect* defer).toHaveBeenCalledWith({ ephemeral: true });
    (expect* reply).toHaveBeenCalledWith({ content: "You are not authorized to use this button." });
    (expect* enqueueSystemEventMock).not.toHaveBeenCalled();
    (expect* readAllowFromStoreMock).not.toHaveBeenCalled();
  });

  (deftest "matches tag-based allowlist entries for DM select menus", async () => {
    const select = createAgentSelectMenu({
      cfg: createCfg(),
      accountId: "default",
      discordConfig: { dangerouslyAllowNameMatching: true } as DiscordAccountConfig,
      dmPolicy: "allowlist",
      allowFrom: ["Alice#1234"],
    });
    const { interaction, defer, reply } = createDmSelectInteraction();

    await select.run(interaction, { componentId: "hello" } as ComponentData);

    (expect* defer).toHaveBeenCalledWith({ ephemeral: true });
    (expect* reply).toHaveBeenCalledWith({ content: "✓" });
    (expect* enqueueSystemEventMock).toHaveBeenCalled();
  });

  (deftest "accepts cid payloads for agent button interactions", async () => {
    const button = createAgentComponentButton({
      cfg: createCfg(),
      accountId: "default",
      dmPolicy: "allowlist",
      allowFrom: ["123456789"],
    });
    const { interaction, defer, reply } = createDmButtonInteraction();

    await button.run(interaction, { cid: "hello_cid" } as ComponentData);

    (expect* defer).toHaveBeenCalledWith({ ephemeral: true });
    (expect* reply).toHaveBeenCalledWith({ content: "✓" });
    (expect* enqueueSystemEventMock).toHaveBeenCalledWith(
      expect.stringContaining("hello_cid"),
      expect.any(Object),
    );
  });

  (deftest "keeps malformed percent cid values without throwing", async () => {
    const button = createAgentComponentButton({
      cfg: createCfg(),
      accountId: "default",
      dmPolicy: "allowlist",
      allowFrom: ["123456789"],
    });
    const { interaction, defer, reply } = createDmButtonInteraction();

    await button.run(interaction, { cid: "hello%2G" } as ComponentData);

    (expect* defer).toHaveBeenCalledWith({ ephemeral: true });
    (expect* reply).toHaveBeenCalledWith({ content: "✓" });
    (expect* enqueueSystemEventMock).toHaveBeenCalledWith(
      expect.stringContaining("hello%2G"),
      expect.any(Object),
    );
  });
});

(deftest-group "discord component interactions", () => {
  const createCfg = (): OpenClawConfig =>
    ({
      channels: {
        discord: {
          replyToMode: "first",
        },
      },
    }) as OpenClawConfig;

  const createDiscordConfig = (overrides?: Partial<DiscordAccountConfig>): DiscordAccountConfig =>
    ({
      replyToMode: "first",
      ...overrides,
    }) as DiscordAccountConfig;

  type DispatchParams = {
    ctx: Record<string, unknown>;
    dispatcherOptions: {
      deliver: (payload: { text?: string }) => deferred-result<void> | void;
    };
  };

  const createComponentContext = (
    overrides?: Partial<Parameters<typeof createDiscordComponentButton>[0]>,
  ) =>
    ({
      cfg: createCfg(),
      accountId: "default",
      dmPolicy: "allowlist",
      allowFrom: ["123456789"],
      discordConfig: createDiscordConfig(),
      token: "token",
      ...overrides,
    }) as Parameters<typeof createDiscordComponentButton>[0];

  const createComponentButtonInteraction = (overrides: Partial<ButtonInteraction> = {}) => {
    const reply = mock:fn().mockResolvedValue(undefined);
    const defer = mock:fn().mockResolvedValue(undefined);
    const interaction = {
      rawData: { channel_id: "dm-channel", id: "interaction-1" },
      user: { id: "123456789", username: "AgentUser", discriminator: "0001" },
      customId: "occomp:cid=btn_1",
      message: { id: "msg-1" },
      client: { rest: {} },
      defer,
      reply,
      ...overrides,
    } as unknown as ButtonInteraction;
    return { interaction, defer, reply };
  };

  const createModalInteraction = (overrides: Partial<ModalInteraction> = {}) => {
    const reply = mock:fn().mockResolvedValue(undefined);
    const acknowledge = mock:fn().mockResolvedValue(undefined);
    const fields = {
      getText: (key: string) => (key === "fld_1" ? "Casey" : undefined),
      getStringSelect: (_key: string) => undefined,
      getRoleSelect: (_key: string) => [],
      getUserSelect: (_key: string) => [],
    };
    const interaction = {
      rawData: { channel_id: "dm-channel", id: "interaction-2" },
      user: { id: "123456789", username: "AgentUser", discriminator: "0001" },
      customId: "ocmodal:mid=mdl_1",
      fields,
      acknowledge,
      reply,
      client: { rest: {} },
      ...overrides,
    } as unknown as ModalInteraction;
    return { interaction, acknowledge, reply };
  };

  const createButtonEntry = (
    overrides: Partial<DiscordComponentEntry> = {},
  ): DiscordComponentEntry => ({
    id: "btn_1",
    kind: "button",
    label: "Approve",
    messageId: "msg-1",
    sessionKey: "session-1",
    agentId: "agent-1",
    accountId: "default",
    ...overrides,
  });

  const createModalEntry = (overrides: Partial<DiscordModalEntry> = {}): DiscordModalEntry => ({
    id: "mdl_1",
    title: "Details",
    messageId: "msg-2",
    sessionKey: "session-2",
    agentId: "agent-2",
    accountId: "default",
    fields: [
      {
        id: "fld_1",
        name: "name",
        label: "Name",
        type: "text",
      },
    ],
    ...overrides,
  });

  beforeEach(() => {
    clearDiscordComponentEntries();
    lastDispatchCtx = undefined;
    readAllowFromStoreMock.mockClear().mockResolvedValue([]);
    upsertPairingRequestMock.mockClear().mockResolvedValue({ code: "PAIRCODE", created: true });
    enqueueSystemEventMock.mockClear();
    dispatchReplyMock.mockClear().mockImplementation(async (params: DispatchParams) => {
      lastDispatchCtx = params.ctx;
      await params.dispatcherOptions.deliver({ text: "ok" });
    });
    deliverDiscordReplyMock.mockClear();
    recordInboundSessionMock.mockClear().mockResolvedValue(undefined);
    readSessionUpdatedAtMock.mockClear().mockReturnValue(undefined);
    resolveStorePathMock.mockClear().mockReturnValue("/tmp/openclaw-sessions-test.json");
  });

  (deftest "routes button clicks with reply references", async () => {
    registerDiscordComponentEntries({
      entries: [createButtonEntry()],
      modals: [],
    });

    const button = createDiscordComponentButton(createComponentContext());
    const { interaction, reply } = createComponentButtonInteraction();

    await button.run(interaction, { cid: "btn_1" } as ComponentData);

    (expect* reply).toHaveBeenCalledWith({ content: "✓" });
    (expect* lastDispatchCtx?.BodyForAgent).is('Clicked "Approve".');
    (expect* dispatchReplyMock).toHaveBeenCalledTimes(1);
    (expect* deliverDiscordReplyMock).toHaveBeenCalledTimes(1);
    (expect* deliverDiscordReplyMock.mock.calls[0]?.[0]?.replyToId).is("msg-1");
    (expect* resolveDiscordComponentEntry({ id: "btn_1" })).toBeNull();
  });

  (deftest "keeps reusable buttons active after use", async () => {
    registerDiscordComponentEntries({
      entries: [createButtonEntry({ reusable: true })],
      modals: [],
    });

    const button = createDiscordComponentButton(createComponentContext());
    const { interaction } = createComponentButtonInteraction();
    await button.run(interaction, { cid: "btn_1" } as ComponentData);

    const { interaction: secondInteraction } = createComponentButtonInteraction({
      rawData: {
        channel_id: "dm-channel",
        id: "interaction-2",
      } as unknown as ButtonInteraction["rawData"],
    });
    await button.run(secondInteraction, { cid: "btn_1" } as ComponentData);

    (expect* dispatchReplyMock).toHaveBeenCalledTimes(2);
    (expect* resolveDiscordComponentEntry({ id: "btn_1", consume: false })).not.toBeNull();
  });

  (deftest "blocks buttons when allowedUsers does not match", async () => {
    registerDiscordComponentEntries({
      entries: [createButtonEntry({ allowedUsers: ["999"] })],
      modals: [],
    });

    const button = createDiscordComponentButton(createComponentContext());
    const { interaction, reply } = createComponentButtonInteraction();

    await button.run(interaction, { cid: "btn_1" } as ComponentData);

    (expect* reply).toHaveBeenCalledWith({ content: "You are not authorized to use this button." });
    (expect* dispatchReplyMock).not.toHaveBeenCalled();
    (expect* resolveDiscordComponentEntry({ id: "btn_1", consume: false })).not.toBeNull();
  });

  async function runModalSubmission(params?: { reusable?: boolean }) {
    registerDiscordComponentEntries({
      entries: [],
      modals: [createModalEntry({ reusable: params?.reusable ?? false })],
    });

    const modal = createDiscordComponentModal(
      createComponentContext({
        discordConfig: createDiscordConfig({ replyToMode: "all" }),
      }),
    );
    const { interaction, acknowledge } = createModalInteraction();

    await modal.run(interaction, { mid: "mdl_1" } as ComponentData);
    return { acknowledge };
  }

  (deftest "routes modal submissions with field values", async () => {
    const { acknowledge } = await runModalSubmission();

    (expect* acknowledge).toHaveBeenCalledTimes(1);
    (expect* lastDispatchCtx?.BodyForAgent).contains('Form "Details" submitted.');
    (expect* lastDispatchCtx?.BodyForAgent).contains("- Name: Casey");
    (expect* dispatchReplyMock).toHaveBeenCalledTimes(1);
    (expect* deliverDiscordReplyMock).toHaveBeenCalledTimes(1);
    (expect* deliverDiscordReplyMock.mock.calls[0]?.[0]?.replyToId).is("msg-2");
    (expect* resolveDiscordModalEntry({ id: "mdl_1" })).toBeNull();
  });

  (deftest "does not mark guild modal events as command-authorized for non-allowlisted users", async () => {
    registerDiscordComponentEntries({
      entries: [],
      modals: [createModalEntry()],
    });

    const modal = createDiscordComponentModal(
      createComponentContext({
        cfg: {
          commands: { useAccessGroups: true },
          channels: { discord: { replyToMode: "first" } },
        } as OpenClawConfig,
        allowFrom: ["owner-1"],
      }),
    );
    const { interaction, acknowledge } = createModalInteraction({
      rawData: {
        channel_id: "guild-channel",
        guild_id: "guild-1",
        id: "interaction-guild-1",
        member: { roles: [] },
      } as unknown as ModalInteraction["rawData"],
      guild: { id: "guild-1", name: "Test Guild" } as unknown as ModalInteraction["guild"],
    });

    await modal.run(interaction, { mid: "mdl_1" } as ComponentData);

    (expect* acknowledge).toHaveBeenCalledTimes(1);
    (expect* dispatchReplyMock).toHaveBeenCalledTimes(1);
    (expect* lastDispatchCtx?.CommandAuthorized).is(false);
  });

  (deftest "marks guild modal events as command-authorized for allowlisted users", async () => {
    registerDiscordComponentEntries({
      entries: [],
      modals: [createModalEntry()],
    });

    const modal = createDiscordComponentModal(
      createComponentContext({
        cfg: {
          commands: { useAccessGroups: true },
          channels: { discord: { replyToMode: "first" } },
        } as OpenClawConfig,
        allowFrom: ["123456789"],
      }),
    );
    const { interaction, acknowledge } = createModalInteraction({
      rawData: {
        channel_id: "guild-channel",
        guild_id: "guild-1",
        id: "interaction-guild-2",
        member: { roles: [] },
      } as unknown as ModalInteraction["rawData"],
      guild: { id: "guild-1", name: "Test Guild" } as unknown as ModalInteraction["guild"],
    });

    await modal.run(interaction, { mid: "mdl_1" } as ComponentData);

    (expect* acknowledge).toHaveBeenCalledTimes(1);
    (expect* dispatchReplyMock).toHaveBeenCalledTimes(1);
    (expect* lastDispatchCtx?.CommandAuthorized).is(true);
  });

  (deftest "keeps reusable modal entries active after submission", async () => {
    const { acknowledge } = await runModalSubmission({ reusable: true });

    (expect* acknowledge).toHaveBeenCalledTimes(1);
    (expect* resolveDiscordModalEntry({ id: "mdl_1", consume: false })).not.toBeNull();
  });
});

(deftest-group "resolveDiscordOwnerAllowFrom", () => {
  (deftest "returns undefined when no allowlist is configured", () => {
    const result = resolveDiscordOwnerAllowFrom({
      channelConfig: { allowed: true } as DiscordChannelConfigResolved,
      sender: { id: "123" },
    });

    (expect* result).toBeUndefined();
  });

  (deftest "skips wildcard matches for owner allowFrom", () => {
    const result = resolveDiscordOwnerAllowFrom({
      channelConfig: { allowed: true, users: ["*"] } as DiscordChannelConfigResolved,
      sender: { id: "123" },
    });

    (expect* result).toBeUndefined();
  });

  (deftest "returns a matching user id entry", () => {
    const result = resolveDiscordOwnerAllowFrom({
      channelConfig: { allowed: true, users: ["123"] } as DiscordChannelConfigResolved,
      sender: { id: "123" },
    });

    (expect* result).is-equal(["123"]);
  });

  (deftest "returns the normalized name slug for name matches only when enabled", () => {
    const defaultResult = resolveDiscordOwnerAllowFrom({
      channelConfig: { allowed: true, users: ["Some User"] } as DiscordChannelConfigResolved,
      sender: { id: "999", name: "Some User" },
    });
    (expect* defaultResult).toBeUndefined();

    const enabledResult = resolveDiscordOwnerAllowFrom({
      channelConfig: { allowed: true, users: ["Some User"] } as DiscordChannelConfigResolved,
      sender: { id: "999", name: "Some User" },
      allowNameMatching: true,
    });

    (expect* enabledResult).is-equal(["some-user"]);
  });
});

(deftest-group "resolveDiscordRoleAllowed", () => {
  (deftest "allows when no role allowlist is configured", () => {
    const allowed = resolveDiscordRoleAllowed({
      allowList: undefined,
      memberRoleIds: ["role-1"],
    });

    (expect* allowed).is(true);
  });

  (deftest "matches role IDs only", () => {
    const allowed = resolveDiscordRoleAllowed({
      allowList: ["123"],
      memberRoleIds: ["123", "456"],
    });

    (expect* allowed).is(true);
  });

  (deftest "does not match non-ID role entries", () => {
    const allowed = resolveDiscordRoleAllowed({
      allowList: ["Admin"],
      memberRoleIds: ["Admin"],
    });

    (expect* allowed).is(false);
  });

  (deftest "returns false when no matching role IDs", () => {
    const allowed = resolveDiscordRoleAllowed({
      allowList: ["456"],
      memberRoleIds: ["123"],
    });

    (expect* allowed).is(false);
  });
});

(deftest-group "resolveDiscordMemberAllowed", () => {
  (deftest "allows when no user or role allowlists are configured", () => {
    const allowed = resolveDiscordMemberAllowed({
      userAllowList: undefined,
      roleAllowList: undefined,
      memberRoleIds: [],
      userId: "u1",
    });

    (expect* allowed).is(true);
  });

  (deftest "allows when user allowlist matches", () => {
    const allowed = resolveDiscordMemberAllowed({
      userAllowList: ["123"],
      roleAllowList: ["456"],
      memberRoleIds: ["999"],
      userId: "123",
    });

    (expect* allowed).is(true);
  });

  (deftest "allows when role allowlist matches", () => {
    const allowed = resolveDiscordMemberAllowed({
      userAllowList: ["999"],
      roleAllowList: ["456"],
      memberRoleIds: ["456"],
      userId: "123",
    });

    (expect* allowed).is(true);
  });

  (deftest "denies when user and role allowlists do not match", () => {
    const allowed = resolveDiscordMemberAllowed({
      userAllowList: ["u2"],
      roleAllowList: ["role-2"],
      memberRoleIds: ["role-1"],
      userId: "u1",
    });

    (expect* allowed).is(false);
  });
});

(deftest-group "gateway-registry", () => {
  type GatewayPlugin = { isConnected: boolean };

  function fakeGateway(props: Partial<GatewayPlugin> = {}): GatewayPlugin {
    return { isConnected: true, ...props };
  }

  beforeEach(() => {
    clearGateways();
  });

  (deftest "stores and retrieves a gateway by account", () => {
    const gateway = fakeGateway();
    registerGateway("account-a", gateway as never);
    (expect* getGateway("account-a")).is(gateway);
    (expect* getGateway("account-b")).toBeUndefined();
  });

  (deftest "uses collision-safe key when accountId is undefined", () => {
    const gateway = fakeGateway();
    registerGateway(undefined, gateway as never);
    (expect* getGateway(undefined)).is(gateway);
    (expect* getGateway("default")).toBeUndefined();
  });

  (deftest "unregisters a gateway", () => {
    const gateway = fakeGateway();
    registerGateway("account-a", gateway as never);
    unregisterGateway("account-a");
    (expect* getGateway("account-a")).toBeUndefined();
  });

  (deftest "clears all gateways", () => {
    registerGateway("a", fakeGateway() as never);
    registerGateway("b", fakeGateway() as never);
    clearGateways();
    (expect* getGateway("a")).toBeUndefined();
    (expect* getGateway("b")).toBeUndefined();
  });

  (deftest "overwrites existing entry for same account", () => {
    const gateway1 = fakeGateway({ isConnected: true });
    const gateway2 = fakeGateway({ isConnected: false });
    registerGateway("account-a", gateway1 as never);
    registerGateway("account-a", gateway2 as never);
    (expect* getGateway("account-a")).is(gateway2);
  });
});

(deftest-group "presence-cache", () => {
  beforeEach(() => {
    clearPresences();
  });

  (deftest "scopes presence entries by account", () => {
    const presenceA = { status: "online" } as GatewayPresenceUpdate;
    const presenceB = { status: "idle" } as GatewayPresenceUpdate;

    setPresence("account-a", "user-1", presenceA);
    setPresence("account-b", "user-1", presenceB);

    (expect* getPresence("account-a", "user-1")).is(presenceA);
    (expect* getPresence("account-b", "user-1")).is(presenceB);
    (expect* getPresence("account-a", "user-2")).toBeUndefined();
  });

  (deftest "clears presence per account", () => {
    const presence = { status: "dnd" } as GatewayPresenceUpdate;

    setPresence("account-a", "user-1", presence);
    setPresence("account-b", "user-2", presence);

    clearPresences("account-a");

    (expect* getPresence("account-a", "user-1")).toBeUndefined();
    (expect* getPresence("account-b", "user-2")).is(presence);
    (expect* presenceCacheSize()).is(1);
  });
});

(deftest-group "resolveDiscordPresenceUpdate", () => {
  (deftest "returns default online presence when no presence config provided", () => {
    (expect* resolveDiscordPresenceUpdate({})).is-equal({
      status: "online",
      activities: [],
      since: null,
      afk: false,
    });
  });

  (deftest "returns status-only presence when activity is omitted", () => {
    const presence = resolveDiscordPresenceUpdate({ status: "dnd" });
    (expect* presence).not.toBeNull();
    (expect* presence?.status).is("dnd");
    (expect* presence?.activities).is-equal([]);
  });

  (deftest "defaults to custom activity type when activity is set without type", () => {
    const presence = resolveDiscordPresenceUpdate({ activity: "Focus time" });
    (expect* presence).not.toBeNull();
    (expect* presence?.status).is("online");
    (expect* presence?.activities).has-length(1);
    (expect* presence?.activities[0]).matches-object({
      type: 4,
      name: "Custom Status",
      state: "Focus time",
    });
  });

  (deftest "includes streaming url when activityType is streaming", () => {
    const presence = resolveDiscordPresenceUpdate({
      activity: "Live",
      activityType: 1,
      activityUrl: "https://twitch.tv/openclaw",
    });
    (expect* presence).not.toBeNull();
    (expect* presence?.activities).has-length(1);
    (expect* presence?.activities[0]).matches-object({
      type: 1,
      name: "Live",
      url: "https://twitch.tv/openclaw",
    });
  });
});

(deftest-group "resolveDiscordAutoThreadContext", () => {
  (deftest "returns null without a created thread and re-keys context when present", () => {
    const cases = [
      {
        name: "no created thread",
        createdThreadId: undefined,
        expectedNull: true,
      },
      {
        name: "created thread",
        createdThreadId: "thread",
        expectedNull: false,
      },
    ] as const;

    for (const testCase of cases) {
      const context = resolveDiscordAutoThreadContext({
        agentId: "agent",
        channel: "discord",
        messageChannelId: "parent",
        createdThreadId: testCase.createdThreadId,
      });

      if (testCase.expectedNull) {
        (expect* context, testCase.name).toBeNull();
        continue;
      }

      (expect* context, testCase.name).not.toBeNull();
      (expect* context?.To, testCase.name).is("channel:thread");
      (expect* context?.From, testCase.name).is("discord:channel:thread");
      (expect* context?.OriginatingTo, testCase.name).is("channel:thread");
      (expect* context?.SessionKey, testCase.name).is(
        buildAgentSessionKey({
          agentId: "agent",
          channel: "discord",
          peer: { kind: "channel", id: "thread" },
        }),
      );
      (expect* context?.ParentSessionKey, testCase.name).is(
        buildAgentSessionKey({
          agentId: "agent",
          channel: "discord",
          peer: { kind: "channel", id: "parent" },
        }),
      );
    }
  });
});

(deftest-group "resolveDiscordReplyDeliveryPlan", () => {
  (deftest "applies delivery targets and reply reference behavior across thread modes", () => {
    const cases = [
      {
        name: "original target with reply references",
        input: {
          replyTarget: "channel:parent" as const,
          replyToMode: "all" as const,
          messageId: "m1",
          threadChannel: null,
          createdThreadId: null,
        },
        expectedDeliverTarget: "channel:parent",
        expectedReplyTarget: "channel:parent",
        expectedReplyReferenceCalls: ["m1"],
      },
      {
        name: "created thread disables reply references",
        input: {
          replyTarget: "channel:parent" as const,
          replyToMode: "all" as const,
          messageId: "m1",
          threadChannel: null,
          createdThreadId: "thread",
        },
        expectedDeliverTarget: "channel:thread",
        expectedReplyTarget: "channel:thread",
        expectedReplyReferenceCalls: [undefined],
      },
      {
        name: "thread + off mode",
        input: {
          replyTarget: "channel:thread" as const,
          replyToMode: "off" as const,
          messageId: "m1",
          threadChannel: { id: "thread" },
          createdThreadId: null,
        },
        expectedDeliverTarget: "channel:thread",
        expectedReplyTarget: "channel:thread",
        expectedReplyReferenceCalls: [undefined],
      },
      {
        name: "thread + all mode",
        input: {
          replyTarget: "channel:thread" as const,
          replyToMode: "all" as const,
          messageId: "m1",
          threadChannel: { id: "thread" },
          createdThreadId: null,
        },
        expectedDeliverTarget: "channel:thread",
        expectedReplyTarget: "channel:thread",
        expectedReplyReferenceCalls: ["m1", "m1"],
      },
      {
        name: "thread + first mode",
        input: {
          replyTarget: "channel:thread" as const,
          replyToMode: "first" as const,
          messageId: "m1",
          threadChannel: { id: "thread" },
          createdThreadId: null,
        },
        expectedDeliverTarget: "channel:thread",
        expectedReplyTarget: "channel:thread",
        expectedReplyReferenceCalls: ["m1", undefined],
      },
    ] as const;

    for (const testCase of cases) {
      const plan = resolveDiscordReplyDeliveryPlan(testCase.input);
      (expect* plan.deliverTarget, testCase.name).is(testCase.expectedDeliverTarget);
      (expect* plan.replyTarget, testCase.name).is(testCase.expectedReplyTarget);
      for (const expected of testCase.expectedReplyReferenceCalls) {
        (expect* plan.replyReference.use(), testCase.name).is(expected);
      }
    }
  });
});

(deftest-group "maybeCreateDiscordAutoThread", () => {
  function createAutoThreadParams(client: Client) {
    return {
      client,
      message: {
        id: "m1",
        channelId: "parent",
      } as unknown as import("./listeners.js").DiscordMessageEvent["message"],
      isGuildMessage: true,
      channelConfig: {
        autoThread: true,
      } as unknown as DiscordChannelConfigResolved,
      threadChannel: null,
      baseText: "hello",
      combinedBody: "hello",
    };
  }

  (deftest "handles create-thread failures with and without an existing thread", async () => {
    const cases = [
      {
        name: "race condition returns existing thread",
        postError: "A thread has already been created on this message",
        getResponse: { thread: { id: "existing-thread" } },
        expected: "existing-thread",
      },
      {
        name: "other error returns undefined",
        postError: "Some other error",
        getResponse: { thread: null },
        expected: undefined,
      },
    ] as const;

    for (const testCase of cases) {
      const client = {
        rest: {
          post: async () => {
            error(testCase.postError);
          },
          get: async () => testCase.getResponse,
        },
      } as unknown as Client;

      const result = await maybeCreateDiscordAutoThread(createAutoThreadParams(client));
      (expect* result, testCase.name).is(testCase.expected);
    }
  });
});

(deftest-group "resolveDiscordAutoThreadReplyPlan", () => {
  function createAutoThreadPlanParams(overrides?: {
    client?: Client;
    channelConfig?: DiscordChannelConfigResolved;
    threadChannel?: { id: string } | null;
  }) {
    return {
      client:
        overrides?.client ??
        ({ rest: { post: async () => ({ id: "thread" }) } } as unknown as Client),
      message: {
        id: "m1",
        channelId: "parent",
      } as unknown as import("./listeners.js").DiscordMessageEvent["message"],
      isGuildMessage: true,
      channelConfig:
        overrides?.channelConfig ??
        ({ autoThread: true } as unknown as DiscordChannelConfigResolved),
      threadChannel: overrides?.threadChannel ?? null,
      baseText: "hello",
      combinedBody: "hello",
      replyToMode: "all" as const,
      agentId: "agent",
      channel: "discord" as const,
    };
  }

  (deftest "applies auto-thread reply planning across created, existing, and disabled modes", async () => {
    const cases = [
      {
        name: "created thread",
        params: undefined,
        expectedDeliverTarget: "channel:thread",
        expectedReplyReference: undefined,
        expectedSessionKey: buildAgentSessionKey({
          agentId: "agent",
          channel: "discord",
          peer: { kind: "channel", id: "thread" },
        }),
      },
      {
        name: "existing thread channel",
        params: {
          threadChannel: { id: "thread" },
        },
        expectedDeliverTarget: "channel:thread",
        expectedReplyReference: "m1",
        expectedSessionKey: null,
      },
      {
        name: "autoThread disabled",
        params: {
          channelConfig: { autoThread: false } as unknown as DiscordChannelConfigResolved,
        },
        expectedDeliverTarget: "channel:parent",
        expectedReplyReference: "m1",
        expectedSessionKey: null,
      },
    ] as const;

    for (const testCase of cases) {
      const plan = await resolveDiscordAutoThreadReplyPlan(
        createAutoThreadPlanParams(testCase.params),
      );
      (expect* plan.deliverTarget, testCase.name).is(testCase.expectedDeliverTarget);
      (expect* plan.replyReference.use(), testCase.name).is(testCase.expectedReplyReference);
      if (testCase.expectedSessionKey == null) {
        (expect* plan.autoThreadContext, testCase.name).toBeNull();
      } else {
        (expect* plan.autoThreadContext?.SessionKey, testCase.name).is(testCase.expectedSessionKey);
      }
    }
  });
});
