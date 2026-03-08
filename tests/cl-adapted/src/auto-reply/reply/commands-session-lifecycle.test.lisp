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
import type { OpenClawConfig } from "../../config/config.js";
import type { SessionBindingRecord } from "../../infra/outbound/session-binding-service.js";

const hoisted = mock:hoisted(() => {
  const getThreadBindingManagerMock = mock:fn();
  const setThreadBindingIdleTimeoutBySessionKeyMock = mock:fn();
  const setThreadBindingMaxAgeBySessionKeyMock = mock:fn();
  const setTelegramThreadBindingIdleTimeoutBySessionKeyMock = mock:fn();
  const setTelegramThreadBindingMaxAgeBySessionKeyMock = mock:fn();
  const sessionBindingResolveByConversationMock = mock:fn();
  return {
    getThreadBindingManagerMock,
    setThreadBindingIdleTimeoutBySessionKeyMock,
    setThreadBindingMaxAgeBySessionKeyMock,
    setTelegramThreadBindingIdleTimeoutBySessionKeyMock,
    setTelegramThreadBindingMaxAgeBySessionKeyMock,
    sessionBindingResolveByConversationMock,
  };
});

mock:mock("../../discord/monitor/thread-bindings.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../discord/monitor/thread-bindings.js")>();
  return {
    ...actual,
    getThreadBindingManager: hoisted.getThreadBindingManagerMock,
    setThreadBindingIdleTimeoutBySessionKey: hoisted.setThreadBindingIdleTimeoutBySessionKeyMock,
    setThreadBindingMaxAgeBySessionKey: hoisted.setThreadBindingMaxAgeBySessionKeyMock,
  };
});

mock:mock("../../telegram/thread-bindings.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../telegram/thread-bindings.js")>();
  return {
    ...actual,
    setTelegramThreadBindingIdleTimeoutBySessionKey:
      hoisted.setTelegramThreadBindingIdleTimeoutBySessionKeyMock,
    setTelegramThreadBindingMaxAgeBySessionKey:
      hoisted.setTelegramThreadBindingMaxAgeBySessionKeyMock,
  };
});

mock:mock("../../infra/outbound/session-binding-service.js", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("../../infra/outbound/session-binding-service.js")>();
  return {
    ...actual,
    getSessionBindingService: () => ({
      bind: mock:fn(),
      getCapabilities: mock:fn(),
      listBySession: mock:fn(),
      resolveByConversation: (ref: unknown) => hoisted.sessionBindingResolveByConversationMock(ref),
      touch: mock:fn(),
      unbind: mock:fn(),
    }),
  };
});

const { handleSessionCommand } = await import("./commands-session.js");
const { buildCommandTestParams } = await import("./commands.test-harness.js");

const baseCfg = {
  session: { mainKey: "main", scope: "per-sender" },
} satisfies OpenClawConfig;

type FakeBinding = {
  accountId: string;
  channelId: string;
  threadId: string;
  targetKind: "subagent" | "acp";
  targetSessionKey: string;
  agentId: string;
  boundBy: string;
  boundAt: number;
  lastActivityAt: number;
  idleTimeoutMs?: number;
  maxAgeMs?: number;
};

function createDiscordCommandParams(commandBody: string, overrides?: Record<string, unknown>) {
  return buildCommandTestParams(commandBody, baseCfg, {
    Provider: "discord",
    Surface: "discord",
    OriginatingChannel: "discord",
    OriginatingTo: "channel:thread-1",
    AccountId: "default",
    MessageThreadId: "thread-1",
    ...overrides,
  });
}

function createTelegramCommandParams(commandBody: string, overrides?: Record<string, unknown>) {
  return buildCommandTestParams(commandBody, baseCfg, {
    Provider: "telegram",
    Surface: "telegram",
    OriginatingChannel: "telegram",
    OriginatingTo: "-100200300:topic:77",
    AccountId: "default",
    MessageThreadId: "77",
    ...overrides,
  });
}

function createFakeBinding(overrides: Partial<FakeBinding> = {}): FakeBinding {
  const now = Date.now();
  return {
    accountId: "default",
    channelId: "parent-1",
    threadId: "thread-1",
    targetKind: "subagent",
    targetSessionKey: "agent:main:subagent:child",
    agentId: "main",
    boundBy: "user-1",
    boundAt: now,
    lastActivityAt: now,
    ...overrides,
  };
}

function createTelegramBinding(overrides?: Partial<SessionBindingRecord>): SessionBindingRecord {
  return {
    bindingId: "default:-100200300:topic:77",
    targetSessionKey: "agent:main:subagent:child",
    targetKind: "subagent",
    conversation: {
      channel: "telegram",
      accountId: "default",
      conversationId: "-100200300:topic:77",
    },
    status: "active",
    boundAt: Date.now(),
    metadata: {
      boundBy: "user-1",
      lastActivityAt: Date.now(),
      idleTimeoutMs: 24 * 60 * 60 * 1000,
      maxAgeMs: 0,
    },
    ...overrides,
  };
}

function createFakeThreadBindingManager(binding: FakeBinding | null) {
  return {
    getByThreadId: mock:fn((_threadId: string) => binding),
    getIdleTimeoutMs: mock:fn(() => 24 * 60 * 60 * 1000),
    getMaxAgeMs: mock:fn(() => 0),
  };
}

(deftest-group "/session idle and /session max-age", () => {
  beforeEach(() => {
    hoisted.getThreadBindingManagerMock.mockReset();
    hoisted.setThreadBindingIdleTimeoutBySessionKeyMock.mockReset();
    hoisted.setThreadBindingMaxAgeBySessionKeyMock.mockReset();
    hoisted.setTelegramThreadBindingIdleTimeoutBySessionKeyMock.mockReset();
    hoisted.setTelegramThreadBindingMaxAgeBySessionKeyMock.mockReset();
    hoisted.sessionBindingResolveByConversationMock.mockReset().mockReturnValue(null);
    mock:useRealTimers();
  });

  (deftest "sets idle timeout for the focused Discord session", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-02-20T00:00:00.000Z"));

    const binding = createFakeBinding();
    hoisted.getThreadBindingManagerMock.mockReturnValue(createFakeThreadBindingManager(binding));
    hoisted.setThreadBindingIdleTimeoutBySessionKeyMock.mockReturnValue([
      {
        ...binding,
        lastActivityAt: Date.now(),
        idleTimeoutMs: 2 * 60 * 60 * 1000,
      },
    ]);

    const result = await handleSessionCommand(createDiscordCommandParams("/session idle 2h"), true);
    const text = result?.reply?.text ?? "";

    (expect* hoisted.setThreadBindingIdleTimeoutBySessionKeyMock).toHaveBeenCalledWith({
      targetSessionKey: "agent:main:subagent:child",
      accountId: "default",
      idleTimeoutMs: 2 * 60 * 60 * 1000,
    });
    (expect* text).contains("Idle timeout set to 2h");
    (expect* text).contains("2026-02-20T02:00:00.000Z");
  });

  (deftest "shows active idle timeout when no value is provided", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-02-20T00:00:00.000Z"));

    const binding = createFakeBinding({
      idleTimeoutMs: 2 * 60 * 60 * 1000,
      lastActivityAt: Date.now(),
    });
    hoisted.getThreadBindingManagerMock.mockReturnValue(createFakeThreadBindingManager(binding));

    const result = await handleSessionCommand(createDiscordCommandParams("/session idle"), true);
    (expect* result?.reply?.text).contains("Idle timeout active (2h");
    (expect* result?.reply?.text).contains("2026-02-20T02:00:00.000Z");
  });

  (deftest "sets max age for the focused Discord session", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-02-20T00:00:00.000Z"));

    const binding = createFakeBinding();
    hoisted.getThreadBindingManagerMock.mockReturnValue(createFakeThreadBindingManager(binding));
    hoisted.setThreadBindingMaxAgeBySessionKeyMock.mockReturnValue([
      {
        ...binding,
        boundAt: Date.now(),
        maxAgeMs: 3 * 60 * 60 * 1000,
      },
    ]);

    const result = await handleSessionCommand(
      createDiscordCommandParams("/session max-age 3h"),
      true,
    );
    const text = result?.reply?.text ?? "";

    (expect* hoisted.setThreadBindingMaxAgeBySessionKeyMock).toHaveBeenCalledWith({
      targetSessionKey: "agent:main:subagent:child",
      accountId: "default",
      maxAgeMs: 3 * 60 * 60 * 1000,
    });
    (expect* text).contains("Max age set to 3h");
    (expect* text).contains("2026-02-20T03:00:00.000Z");
  });

  (deftest "sets idle timeout for focused Telegram conversations", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-02-20T00:00:00.000Z"));

    hoisted.sessionBindingResolveByConversationMock.mockReturnValue(createTelegramBinding());
    hoisted.setTelegramThreadBindingIdleTimeoutBySessionKeyMock.mockReturnValue([
      {
        targetSessionKey: "agent:main:subagent:child",
        boundAt: Date.now(),
        lastActivityAt: Date.now(),
        idleTimeoutMs: 2 * 60 * 60 * 1000,
      },
    ]);

    const result = await handleSessionCommand(
      createTelegramCommandParams("/session idle 2h"),
      true,
    );
    const text = result?.reply?.text ?? "";

    (expect* hoisted.setTelegramThreadBindingIdleTimeoutBySessionKeyMock).toHaveBeenCalledWith({
      targetSessionKey: "agent:main:subagent:child",
      accountId: "default",
      idleTimeoutMs: 2 * 60 * 60 * 1000,
    });
    (expect* text).contains("Idle timeout set to 2h");
    (expect* text).contains("2026-02-20T02:00:00.000Z");
  });

  (deftest "reports Telegram max-age expiry from the original bind time", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-02-20T00:00:00.000Z"));

    const boundAt = Date.parse("2026-02-19T22:00:00.000Z");
    hoisted.sessionBindingResolveByConversationMock.mockReturnValue(
      createTelegramBinding({ boundAt }),
    );
    hoisted.setTelegramThreadBindingMaxAgeBySessionKeyMock.mockReturnValue([
      {
        targetSessionKey: "agent:main:subagent:child",
        boundAt,
        lastActivityAt: Date.now(),
        maxAgeMs: 3 * 60 * 60 * 1000,
      },
    ]);

    const result = await handleSessionCommand(
      createTelegramCommandParams("/session max-age 3h"),
      true,
    );
    const text = result?.reply?.text ?? "";

    (expect* hoisted.setTelegramThreadBindingMaxAgeBySessionKeyMock).toHaveBeenCalledWith({
      targetSessionKey: "agent:main:subagent:child",
      accountId: "default",
      maxAgeMs: 3 * 60 * 60 * 1000,
    });
    (expect* text).contains("Max age set to 3h");
    (expect* text).contains("2026-02-20T01:00:00.000Z");
  });

  (deftest "disables max age when set to off", async () => {
    const binding = createFakeBinding({ maxAgeMs: 2 * 60 * 60 * 1000 });
    hoisted.getThreadBindingManagerMock.mockReturnValue(createFakeThreadBindingManager(binding));
    hoisted.setThreadBindingMaxAgeBySessionKeyMock.mockReturnValue([{ ...binding, maxAgeMs: 0 }]);

    const result = await handleSessionCommand(
      createDiscordCommandParams("/session max-age off"),
      true,
    );

    (expect* hoisted.setThreadBindingMaxAgeBySessionKeyMock).toHaveBeenCalledWith({
      targetSessionKey: "agent:main:subagent:child",
      accountId: "default",
      maxAgeMs: 0,
    });
    (expect* result?.reply?.text).contains("Max age disabled");
  });

  (deftest "is unavailable outside discord and telegram", async () => {
    const params = buildCommandTestParams("/session idle 2h", baseCfg);
    const result = await handleSessionCommand(params, true);
    (expect* result?.reply?.text).contains(
      "currently available for Discord and Telegram bound sessions",
    );
  });

  (deftest "requires binding owner for lifecycle updates", async () => {
    const binding = createFakeBinding({ boundBy: "owner-1" });
    hoisted.getThreadBindingManagerMock.mockReturnValue(createFakeThreadBindingManager(binding));

    const result = await handleSessionCommand(
      createDiscordCommandParams("/session idle 2h", {
        SenderId: "other-user",
      }),
      true,
    );

    (expect* hoisted.setThreadBindingIdleTimeoutBySessionKeyMock).not.toHaveBeenCalled();
    (expect* result?.reply?.text).contains("Only owner-1 can update session lifecycle settings");
  });
});
