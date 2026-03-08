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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";

mock:mock("../../config/sessions.js", () => ({
  loadSessionStore: mock:fn().mockReturnValue({}),
  resolveAgentMainSessionKey: mock:fn().mockReturnValue("agent:test:main"),
  resolveStorePath: mock:fn().mockReturnValue("/tmp/test-store.json"),
}));

mock:mock("../../infra/outbound/channel-selection.js", () => ({
  resolveMessageChannelSelection: vi
    .fn()
    .mockResolvedValue({ channel: "telegram", configured: ["telegram"] }),
}));

mock:mock("../../pairing/pairing-store.js", () => ({
  readChannelAllowFromStoreSync: mock:fn(() => []),
}));

mock:mock("../../web/accounts.js", () => ({
  resolveWhatsAppAccount: mock:fn(() => ({ allowFrom: [] })),
}));

import { loadSessionStore } from "../../config/sessions.js";
import { resolveMessageChannelSelection } from "../../infra/outbound/channel-selection.js";
import { readChannelAllowFromStoreSync } from "../../pairing/pairing-store.js";
import { resolveWhatsAppAccount } from "../../web/accounts.js";
import { resolveDeliveryTarget } from "./delivery-target.js";

function makeCfg(overrides?: Partial<OpenClawConfig>): OpenClawConfig {
  return {
    bindings: [],
    channels: {},
    ...overrides,
  } as OpenClawConfig;
}

function makeTelegramBoundCfg(accountId = "account-b"): OpenClawConfig {
  return makeCfg({
    bindings: [
      {
        agentId: AGENT_ID,
        match: { channel: "telegram", accountId },
      },
    ],
  });
}

const AGENT_ID = "agent-b";
const DEFAULT_TARGET = {
  channel: "telegram" as const,
  to: "123456",
};

type SessionStore = ReturnType<typeof loadSessionStore>;

function setMainSessionEntry(entry?: SessionStore[string]) {
  const store = entry ? ({ "agent:test:main": entry } as SessionStore) : ({} as SessionStore);
  mock:mocked(loadSessionStore).mockReturnValue(store);
}

function setWhatsAppAllowFrom(allowFrom: string[]) {
  mock:mocked(resolveWhatsAppAccount).mockReturnValue({
    allowFrom,
  } as unknown as ReturnType<typeof resolveWhatsAppAccount>);
}

function setStoredWhatsAppAllowFrom(allowFrom: string[]) {
  mock:mocked(readChannelAllowFromStoreSync).mockReturnValue(allowFrom);
}

async function resolveForAgent(params: {
  cfg: OpenClawConfig;
  target?: { channel?: "last" | "telegram"; to?: string };
}) {
  const channel = params.target ? params.target.channel : DEFAULT_TARGET.channel;
  const to = params.target && "to" in params.target ? params.target.to : DEFAULT_TARGET.to;
  return resolveDeliveryTarget(params.cfg, AGENT_ID, {
    channel,
    to,
  });
}

(deftest-group "resolveDeliveryTarget", () => {
  (deftest "reroutes implicit whatsapp delivery to authorized allowFrom recipient", async () => {
    setMainSessionEntry({
      sessionId: "sess-w1",
      updatedAt: 1000,
      lastChannel: "whatsapp",
      lastTo: "+15550000099",
    });
    setWhatsAppAllowFrom([]);
    setStoredWhatsAppAllowFrom(["+15550000001"]);

    const cfg = makeCfg({ bindings: [] });
    const result = await resolveDeliveryTarget(cfg, AGENT_ID, { channel: "last", to: undefined });

    (expect* result.channel).is("whatsapp");
    (expect* result.to).is("+15550000001");
  });

  (deftest "keeps explicit whatsapp target unchanged", async () => {
    setMainSessionEntry({
      sessionId: "sess-w2",
      updatedAt: 1000,
      lastChannel: "whatsapp",
      lastTo: "+15550000099",
    });
    setWhatsAppAllowFrom([]);
    setStoredWhatsAppAllowFrom(["+15550000001"]);

    const cfg = makeCfg({ bindings: [] });
    const result = await resolveDeliveryTarget(cfg, AGENT_ID, {
      channel: "whatsapp",
      to: "+15550000099",
    });

    (expect* result.to).is("+15550000099");
  });

  (deftest "falls back to bound accountId when session has no lastAccountId", async () => {
    setMainSessionEntry(undefined);
    const cfg = makeTelegramBoundCfg();
    const result = await resolveForAgent({ cfg });

    (expect* result.accountId).is("account-b");
  });

  (deftest "preserves session lastAccountId when present", async () => {
    setMainSessionEntry({
      sessionId: "sess-1",
      updatedAt: 1000,
      lastChannel: "telegram",
      lastTo: "123456",
      lastAccountId: "session-account",
    });

    const cfg = makeTelegramBoundCfg();
    const result = await resolveForAgent({ cfg });

    // Session-derived accountId should take precedence over binding
    (expect* result.accountId).is("session-account");
  });

  (deftest "returns undefined accountId when no binding and no session", async () => {
    setMainSessionEntry(undefined);

    const cfg = makeCfg({ bindings: [] });

    const result = await resolveForAgent({ cfg });

    (expect* result.accountId).toBeUndefined();
  });

  (deftest "selects correct binding when multiple agents have bindings", async () => {
    setMainSessionEntry(undefined);

    const cfg = makeCfg({
      bindings: [
        {
          agentId: "agent-a",
          match: { channel: "telegram", accountId: "account-a" },
        },
        {
          agentId: "agent-b",
          match: { channel: "telegram", accountId: "account-b" },
        },
      ],
    });

    const result = await resolveForAgent({ cfg });

    (expect* result.accountId).is("account-b");
  });

  (deftest "ignores bindings for different channels", async () => {
    setMainSessionEntry(undefined);

    const cfg = makeCfg({
      bindings: [
        {
          agentId: "agent-b",
          match: { channel: "discord", accountId: "discord-account" },
        },
      ],
    });

    const result = await resolveForAgent({ cfg });

    (expect* result.accountId).toBeUndefined();
  });

  (deftest "drops session threadId when destination does not match the previous recipient", async () => {
    setMainSessionEntry({
      sessionId: "sess-2",
      updatedAt: 1000,
      lastChannel: "telegram",
      lastTo: "999999",
      lastThreadId: "thread-1",
    });

    const result = await resolveForAgent({ cfg: makeCfg({ bindings: [] }) });
    (expect* result.threadId).toBeUndefined();
  });

  (deftest "keeps session threadId when destination matches the previous recipient", async () => {
    setMainSessionEntry({
      sessionId: "sess-3",
      updatedAt: 1000,
      lastChannel: "telegram",
      lastTo: "123456",
      lastThreadId: "thread-2",
    });

    const result = await resolveForAgent({ cfg: makeCfg({ bindings: [] }) });
    (expect* result.threadId).is("thread-2");
  });

  (deftest "uses single configured channel when neither explicit nor session channel exists", async () => {
    setMainSessionEntry(undefined);

    const result = await resolveForAgent({
      cfg: makeCfg({ bindings: [] }),
      target: { channel: "last", to: undefined },
    });
    (expect* result.channel).is("telegram");
    (expect* result.ok).is(false);
    if (result.ok) {
      error("expected unresolved delivery target");
    }
    // resolveOutboundTarget provides the standard missing-target error when
    // no explicit target, no session lastTo, and no plugin resolveDefaultTo.
    (expect* result.error.message).contains("requires target");
  });

  (deftest "returns an error when channel selection is ambiguous", async () => {
    setMainSessionEntry(undefined);
    mock:mocked(resolveMessageChannelSelection).mockRejectedValueOnce(
      new Error("Channel is required when multiple channels are configured: telegram, slack"),
    );

    const result = await resolveForAgent({
      cfg: makeCfg({ bindings: [] }),
      target: { channel: "last", to: undefined },
    });
    (expect* result.channel).toBeUndefined();
    (expect* result.to).toBeUndefined();
    (expect* result.ok).is(false);
    if (result.ok) {
      error("expected ambiguous channel selection error");
    }
    (expect* result.error.message).contains("Channel is required");
  });

  (deftest "uses sessionKey thread entry before main session entry", async () => {
    mock:mocked(loadSessionStore).mockReturnValue({
      "agent:test:main": {
        sessionId: "main-session",
        updatedAt: 1000,
        lastChannel: "telegram",
        lastTo: "main-chat",
      },
      "agent:test:thread:42": {
        sessionId: "thread-session",
        updatedAt: 2000,
        lastChannel: "telegram",
        lastTo: "thread-chat",
      },
    } as SessionStore);

    const result = await resolveDeliveryTarget(makeCfg({ bindings: [] }), AGENT_ID, {
      channel: "last",
      sessionKey: "agent:test:thread:42",
      to: undefined,
    });

    (expect* result.channel).is("telegram");
    (expect* result.to).is("thread-chat");
  });

  (deftest "uses main session channel when channel=last and session route exists", async () => {
    setMainSessionEntry({
      sessionId: "sess-4",
      updatedAt: 1000,
      lastChannel: "telegram",
      lastTo: "987654",
    });

    const result = await resolveForAgent({
      cfg: makeCfg({ bindings: [] }),
      target: { channel: "last", to: undefined },
    });

    (expect* result.channel).is("telegram");
    (expect* result.to).is("987654");
    (expect* result.ok).is(true);
  });

  (deftest "explicit delivery.accountId overrides session-derived accountId", async () => {
    setMainSessionEntry({
      sessionId: "sess-5",
      updatedAt: 1000,
      lastChannel: "telegram",
      lastTo: "chat-999",
      lastAccountId: "default",
    });

    const result = await resolveDeliveryTarget(makeCfg({ bindings: [] }), AGENT_ID, {
      channel: "telegram",
      to: "chat-999",
      accountId: "bot-b",
    });

    (expect* result.ok).is(true);
    (expect* result.accountId).is("bot-b");
  });

  (deftest "explicit delivery.accountId overrides bindings-derived accountId", async () => {
    setMainSessionEntry(undefined);
    const cfg = makeCfg({
      bindings: [{ agentId: AGENT_ID, match: { channel: "telegram", accountId: "bound" } }],
    });

    const result = await resolveDeliveryTarget(cfg, AGENT_ID, {
      channel: "telegram",
      to: "chat-777",
      accountId: "explicit",
    });

    (expect* result.ok).is(true);
    (expect* result.accountId).is("explicit");
  });
});
