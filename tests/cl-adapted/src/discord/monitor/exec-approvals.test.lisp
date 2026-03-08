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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import type { ButtonInteraction, ComponentData } from "@buape/carbon";
import { Routes } from "discord-api-types/v10";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { clearSessionStoreCacheForTest } from "../../config/sessions.js";
import type { DiscordExecApprovalConfig } from "../../config/types.discord.js";
import {
  buildExecApprovalCustomId,
  extractDiscordChannelId,
  parseExecApprovalData,
  type ExecApprovalRequest,
  DiscordExecApprovalHandler,
  ExecApprovalButton,
  type ExecApprovalButtonContext,
} from "./exec-approvals.js";

const STORE_PATH = path.join(os.tmpdir(), "openclaw-exec-approvals-test.json");

const writeStore = (store: Record<string, unknown>) => {
  fs.writeFileSync(STORE_PATH, `${JSON.stringify(store, null, 2)}\n`, "utf8");
  // CI runners can have coarse mtime resolution; avoid returning stale cached stores.
  clearSessionStoreCacheForTest();
};

beforeEach(() => {
  writeStore({});
  mockGatewayClientCtor.mockClear();
  mockResolveGatewayConnectionAuth.mockReset().mockImplementation(
    async (params: {
      config?: {
        gateway?: {
          auth?: {
            token?: string;
            password?: string;
          };
        };
      };
      env: NodeJS.ProcessEnv;
    }) => {
      const configToken = params.config?.gateway?.auth?.token;
      const configPassword = params.config?.gateway?.auth?.password;
      const envToken = params.env.OPENCLAW_GATEWAY_TOKEN ?? params.env.CLAWDBOT_GATEWAY_TOKEN;
      const envPassword =
        params.env.OPENCLAW_GATEWAY_PASSWORD ?? params.env.CLAWDBOT_GATEWAY_PASSWORD;
      return { token: envToken ?? configToken, password: envPassword ?? configPassword };
    },
  );
});

// ─── Mocks ────────────────────────────────────────────────────────────────────

const mockRestPost = mock:hoisted(() => mock:fn());
const mockRestPatch = mock:hoisted(() => mock:fn());
const mockRestDelete = mock:hoisted(() => mock:fn());
const gatewayClientStarts = mock:hoisted(() => mock:fn());
const gatewayClientStops = mock:hoisted(() => mock:fn());
const gatewayClientRequests = mock:hoisted(() => mock:fn(async () => ({ ok: true })));
const gatewayClientParams = mock:hoisted(() => [] as Array<Record<string, unknown>>);
const mockGatewayClientCtor = mock:hoisted(() => mock:fn());
const mockResolveGatewayConnectionAuth = mock:hoisted(() => mock:fn());

mock:mock("../send.shared.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../send.shared.js")>();
  return {
    ...actual,
    createDiscordClient: () => ({
      rest: {
        post: mockRestPost,
        patch: mockRestPatch,
        delete: mockRestDelete,
      },
      request: (_fn: () => deferred-result<unknown>, _label: string) => _fn(),
    }),
  };
});

mock:mock("../../gateway/client.js", () => ({
  GatewayClient: class {
    private params: Record<string, unknown>;
    constructor(params: Record<string, unknown>) {
      this.params = params;
      gatewayClientParams.push(params);
      mockGatewayClientCtor(params);
    }
    start() {
      gatewayClientStarts();
    }
    stop() {
      gatewayClientStops();
    }
    async request() {
      return gatewayClientRequests();
    }
  },
}));

mock:mock("../../gateway/connection-auth.js", () => ({
  resolveGatewayConnectionAuth: mockResolveGatewayConnectionAuth,
}));

mock:mock("../../logger.js", () => ({
  logDebug: mock:fn(),
  logError: mock:fn(),
}));

// ─── Helpers ──────────────────────────────────────────────────────────────────

function createHandler(config: DiscordExecApprovalConfig, accountId = "default") {
  return new DiscordExecApprovalHandler({
    token: "test-token",
    accountId,
    config,
    cfg: { session: { store: STORE_PATH } },
  });
}

type ExecApprovalHandlerInternals = {
  pending: Map<
    string,
    { discordMessageId: string; discordChannelId: string; timeoutId: NodeJS.Timeout }
  >;
  requestCache: Map<string, ExecApprovalRequest>;
  handleApprovalRequested: (request: ExecApprovalRequest) => deferred-result<void>;
  handleApprovalTimeout: (approvalId: string, source?: "channel" | "dm") => deferred-result<void>;
};

function getHandlerInternals(handler: DiscordExecApprovalHandler): ExecApprovalHandlerInternals {
  return handler as unknown as ExecApprovalHandlerInternals;
}

function clearPendingTimeouts(handler: DiscordExecApprovalHandler) {
  const internals = getHandlerInternals(handler);
  for (const pending of internals.pending.values()) {
    clearTimeout(pending.timeoutId);
  }
  internals.pending.clear();
}

function createRequest(
  overrides: Partial<ExecApprovalRequest["request"]> = {},
): ExecApprovalRequest {
  return {
    id: "test-id",
    request: {
      command: "echo hello",
      cwd: "/home/user",
      host: "gateway",
      agentId: "test-agent",
      sessionKey: "agent:test-agent:discord:channel:999888777",
      ...overrides,
    },
    createdAtMs: Date.now(),
    expiresAtMs: Date.now() + 60000,
  };
}

beforeEach(() => {
  mockRestPost.mockReset();
  mockRestPatch.mockReset();
  mockRestDelete.mockReset();
  gatewayClientStarts.mockReset();
  gatewayClientStops.mockReset();
  gatewayClientRequests.mockReset();
  gatewayClientRequests.mockResolvedValue({ ok: true });
  gatewayClientParams.length = 0;
});

// ─── buildExecApprovalCustomId ────────────────────────────────────────────────

(deftest-group "buildExecApprovalCustomId", () => {
  (deftest "encodes approval id and action", () => {
    const customId = buildExecApprovalCustomId("abc-123", "allow-once");
    (expect* customId).is("execapproval:id=abc-123;action=allow-once");
  });

  (deftest "encodes special characters in approval id", () => {
    const customId = buildExecApprovalCustomId("abc=123;test", "deny");
    (expect* customId).is("execapproval:id=abc%3D123%3Btest;action=deny");
  });
});

// ─── parseExecApprovalData ────────────────────────────────────────────────────

(deftest-group "parseExecApprovalData", () => {
  (deftest "parses valid data", () => {
    const result = parseExecApprovalData({ id: "abc-123", action: "allow-once" });
    (expect* result).is-equal({ approvalId: "abc-123", action: "allow-once" });
  });

  (deftest "parses encoded data", () => {
    const result = parseExecApprovalData({
      id: "abc%3D123%3Btest",
      action: "allow-always",
    });
    (expect* result).is-equal({ approvalId: "abc=123;test", action: "allow-always" });
  });

  (deftest "rejects invalid action", () => {
    const result = parseExecApprovalData({ id: "abc-123", action: "invalid" });
    (expect* result).toBeNull();
  });

  (deftest "rejects missing id", () => {
    const result = parseExecApprovalData({ action: "deny" });
    (expect* result).toBeNull();
  });

  (deftest "rejects missing action", () => {
    const result = parseExecApprovalData({ id: "abc-123" });
    (expect* result).toBeNull();
  });

  (deftest "rejects null/undefined input", () => {
    // oxlint-disable-next-line typescript/no-explicit-any
    (expect* parseExecApprovalData(null as any)).toBeNull();
    // oxlint-disable-next-line typescript/no-explicit-any
    (expect* parseExecApprovalData(undefined as any)).toBeNull();
  });

  (deftest "accepts all valid actions", () => {
    (expect* parseExecApprovalData({ id: "x", action: "allow-once" })?.action).is("allow-once");
    (expect* parseExecApprovalData({ id: "x", action: "allow-always" })?.action).is("allow-always");
    (expect* parseExecApprovalData({ id: "x", action: "deny" })?.action).is("deny");
  });
});

// ─── roundtrip encoding ───────────────────────────────────────────────────────

(deftest-group "roundtrip encoding", () => {
  (deftest "encodes and decodes correctly", () => {
    const approvalId = "test-approval-with=special;chars&more";
    const action = "allow-always" as const;
    const customId = buildExecApprovalCustomId(approvalId, action);

    // Parse the key=value pairs from the custom ID
    const parts = customId.split(";");
    const data: Record<string, string> = {};
    for (const part of parts) {
      const match = part.match(/^([^:]+:)?([^=]+)=(.+)$/);
      if (match) {
        data[match[2]] = match[3];
      }
    }

    const result = parseExecApprovalData(data);
    (expect* result).is-equal({ approvalId, action });
  });
});

// ─── extractDiscordChannelId ──────────────────────────────────────────────────

(deftest-group "extractDiscordChannelId", () => {
  (deftest "extracts channel IDs and rejects invalid session key inputs", () => {
    const cases: Array<{
      name: string;
      input: string | null | undefined;
      expected: string | null;
    }> = [
      {
        name: "standard session key",
        input: "agent:main:discord:channel:123456789",
        expected: "123456789",
      },
      {
        name: "agent-specific session key",
        input: "agent:test-agent:discord:channel:999888777",
        expected: "999888777",
      },
      {
        name: "group session key",
        input: "agent:main:discord:group:222333444",
        expected: "222333444",
      },
      {
        name: "longer session key",
        input: "agent:my-agent:discord:channel:111222333:thread:444555",
        expected: "111222333",
      },
      {
        name: "non-discord session key",
        input: "agent:main:telegram:channel:123456789",
        expected: null,
      },
      {
        name: "missing channel/group segment",
        input: "agent:main:discord:dm:123456789",
        expected: null,
      },
      { name: "null input", input: null, expected: null },
      { name: "undefined input", input: undefined, expected: null },
      { name: "empty input", input: "", expected: null },
    ];

    for (const testCase of cases) {
      (expect* extractDiscordChannelId(testCase.input), testCase.name).is(testCase.expected);
    }
  });
});

// ─── DiscordExecApprovalHandler.shouldHandle ──────────────────────────────────

(deftest-group "DiscordExecApprovalHandler.shouldHandle", () => {
  (deftest "returns false when disabled", () => {
    const handler = createHandler({ enabled: false, approvers: ["123"] });
    (expect* handler.shouldHandle(createRequest())).is(false);
  });

  (deftest "returns false when no approvers", () => {
    const handler = createHandler({ enabled: true, approvers: [] });
    (expect* handler.shouldHandle(createRequest())).is(false);
  });

  (deftest "returns true with minimal config", () => {
    const handler = createHandler({ enabled: true, approvers: ["123"] });
    (expect* handler.shouldHandle(createRequest())).is(true);
  });

  (deftest "filters by agent ID", () => {
    const handler = createHandler({
      enabled: true,
      approvers: ["123"],
      agentFilter: ["allowed-agent"],
    });
    (expect* handler.shouldHandle(createRequest({ agentId: "allowed-agent" }))).is(true);
    (expect* handler.shouldHandle(createRequest({ agentId: "other-agent" }))).is(false);
    (expect* handler.shouldHandle(createRequest({ agentId: null }))).is(false);
  });

  (deftest "filters by session key substring", () => {
    const handler = createHandler({
      enabled: true,
      approvers: ["123"],
      sessionFilter: ["discord"],
    });
    (expect* handler.shouldHandle(createRequest({ sessionKey: "agent:test:discord:123" }))).is(
      true,
    );
    (expect* handler.shouldHandle(createRequest({ sessionKey: "agent:test:telegram:123" }))).is(
      false,
    );
    (expect* handler.shouldHandle(createRequest({ sessionKey: null }))).is(false);
  });

  (deftest "filters by session key regex", () => {
    const handler = createHandler({
      enabled: true,
      approvers: ["123"],
      sessionFilter: ["^agent:.*:discord:"],
    });
    (expect* handler.shouldHandle(createRequest({ sessionKey: "agent:test:discord:123" }))).is(
      true,
    );
    (expect* handler.shouldHandle(createRequest({ sessionKey: "other:test:discord:123" }))).is(
      false,
    );
  });

  (deftest "rejects unsafe nested-repetition regex in session filter", () => {
    const handler = createHandler({
      enabled: true,
      approvers: ["123"],
      sessionFilter: ["(a+)+$"],
    });
    (expect* handler.shouldHandle(createRequest({ sessionKey: `${"a".repeat(28)}!` }))).is(false);
  });

  (deftest "matches long session keys with tail-bounded regex checks", () => {
    const handler = createHandler({
      enabled: true,
      approvers: ["123"],
      sessionFilter: ["discord:tail$"],
    });
    (expect* 
      handler.shouldHandle(createRequest({ sessionKey: `${"x".repeat(5000)}discord:tail` })),
    ).is(true);
  });

  (deftest "filters by discord account when session store includes account", () => {
    writeStore({
      "agent:test-agent:discord:channel:999888777": {
        sessionId: "sess",
        updatedAt: Date.now(),
        origin: { provider: "discord", accountId: "secondary" },
        lastAccountId: "secondary",
      },
    });
    const handler = createHandler({ enabled: true, approvers: ["123"] }, "default");
    (expect* handler.shouldHandle(createRequest())).is(false);
    const matching = createHandler({ enabled: true, approvers: ["123"] }, "secondary");
    (expect* matching.shouldHandle(createRequest())).is(true);
  });

  (deftest "combines agent and session filters", () => {
    const handler = createHandler({
      enabled: true,
      approvers: ["123"],
      agentFilter: ["my-agent"],
      sessionFilter: ["discord"],
    });
    (expect* 
      handler.shouldHandle(
        createRequest({
          agentId: "my-agent",
          sessionKey: "agent:my-agent:discord:123",
        }),
      ),
    ).is(true);
    (expect* 
      handler.shouldHandle(
        createRequest({
          agentId: "other-agent",
          sessionKey: "agent:other:discord:123",
        }),
      ),
    ).is(false);
    (expect* 
      handler.shouldHandle(
        createRequest({
          agentId: "my-agent",
          sessionKey: "agent:my-agent:telegram:123",
        }),
      ),
    ).is(false);
  });
});

// ─── DiscordExecApprovalHandler.getApprovers ──────────────────────────────────

(deftest-group "DiscordExecApprovalHandler.getApprovers", () => {
  (deftest "returns approvers for configured, empty, and undefined lists", () => {
    const cases = [
      {
        name: "configured approvers",
        config: { enabled: true, approvers: ["111", "222"] } as DiscordExecApprovalConfig,
        expected: ["111", "222"],
      },
      {
        name: "empty approvers",
        config: { enabled: true, approvers: [] } as DiscordExecApprovalConfig,
        expected: [],
      },
      {
        name: "undefined approvers",
        config: { enabled: true } as DiscordExecApprovalConfig,
        expected: [],
      },
    ] as const;

    for (const testCase of cases) {
      const handler = createHandler(testCase.config);
      (expect* handler.getApprovers(), testCase.name).is-equal(testCase.expected);
    }
  });
});

// ─── ExecApprovalButton authorization ─────────────────────────────────────────

(deftest-group "ExecApprovalButton", () => {
  function createMockHandler(approverIds: string[]) {
    const handler = createHandler({
      enabled: true,
      approvers: approverIds,
    });
    // Mock resolveApproval to track calls
    handler.resolveApproval = mock:fn().mockResolvedValue(true);
    return handler;
  }

  function createMockInteraction(userId: string) {
    const reply = mock:fn().mockResolvedValue(undefined);
    const update = mock:fn().mockResolvedValue(undefined);
    const followUp = mock:fn().mockResolvedValue(undefined);
    const interaction = {
      userId,
      reply,
      update,
      followUp,
    } as unknown as ButtonInteraction;
    return { interaction, reply, update, followUp };
  }

  (deftest "denies unauthorized users with ephemeral message", async () => {
    const handler = createMockHandler(["111", "222"]);
    const ctx: ExecApprovalButtonContext = { handler };
    const button = new ExecApprovalButton(ctx);

    const { interaction, reply, update } = createMockInteraction("999");
    const data: ComponentData = { id: "test-approval", action: "allow-once" };

    await button.run(interaction, data);

    (expect* reply).toHaveBeenCalledWith({
      content: "⛔ You are not authorized to approve exec requests.",
      ephemeral: true,
    });
    (expect* update).not.toHaveBeenCalled();
    // oxlint-disable-next-line typescript/unbound-method -- mock:fn() mock
    (expect* handler.resolveApproval).not.toHaveBeenCalled();
  });

  (deftest "allows authorized user and resolves approval", async () => {
    const handler = createMockHandler(["111", "222"]);
    const ctx: ExecApprovalButtonContext = { handler };
    const button = new ExecApprovalButton(ctx);

    const { interaction, reply, update } = createMockInteraction("222");
    const data: ComponentData = { id: "test-approval", action: "allow-once" };

    await button.run(interaction, data);

    (expect* reply).not.toHaveBeenCalled();
    (expect* update).toHaveBeenCalledWith({
      content: "Submitting decision: **Allowed (once)**...",
      components: [],
    });
    // oxlint-disable-next-line typescript/unbound-method -- mock:fn() mock
    (expect* handler.resolveApproval).toHaveBeenCalledWith("test-approval", "allow-once");
  });

  (deftest "shows correct label for allow-always", async () => {
    const handler = createMockHandler(["111"]);
    const ctx: ExecApprovalButtonContext = { handler };
    const button = new ExecApprovalButton(ctx);

    const { interaction, update } = createMockInteraction("111");
    const data: ComponentData = { id: "test-approval", action: "allow-always" };

    await button.run(interaction, data);

    (expect* update).toHaveBeenCalledWith({
      content: "Submitting decision: **Allowed (always)**...",
      components: [],
    });
  });

  (deftest "shows correct label for deny", async () => {
    const handler = createMockHandler(["111"]);
    const ctx: ExecApprovalButtonContext = { handler };
    const button = new ExecApprovalButton(ctx);

    const { interaction, update } = createMockInteraction("111");
    const data: ComponentData = { id: "test-approval", action: "deny" };

    await button.run(interaction, data);

    (expect* update).toHaveBeenCalledWith({
      content: "Submitting decision: **Denied**...",
      components: [],
    });
  });

  (deftest "handles invalid data gracefully", async () => {
    const handler = createMockHandler(["111"]);
    const ctx: ExecApprovalButtonContext = { handler };
    const button = new ExecApprovalButton(ctx);

    const { interaction, update } = createMockInteraction("111");
    const data: ComponentData = { id: "", action: "invalid" };

    await button.run(interaction, data);

    (expect* update).toHaveBeenCalledWith({
      content: "This approval is no longer valid.",
      components: [],
    });
    // oxlint-disable-next-line typescript/unbound-method -- mock:fn() mock
    (expect* handler.resolveApproval).not.toHaveBeenCalled();
  });
  (deftest "follows up with error when resolve fails", async () => {
    const handler = createMockHandler(["111"]);
    handler.resolveApproval = mock:fn().mockResolvedValue(false);
    const ctx: ExecApprovalButtonContext = { handler };
    const button = new ExecApprovalButton(ctx);

    const { interaction, followUp } = createMockInteraction("111");
    const data: ComponentData = { id: "test-approval", action: "allow-once" };

    await button.run(interaction, data);

    (expect* followUp).toHaveBeenCalledWith({
      content:
        "Failed to submit approval decision. The request may have expired or already been resolved.",
      ephemeral: true,
    });
  });

  (deftest "matches approvers with string coercion", async () => {
    // Approvers might be numbers in config
    const handler = createHandler({
      enabled: true,
      approvers: [111 as unknown as string],
    });
    handler.resolveApproval = mock:fn().mockResolvedValue(true);
    const ctx: ExecApprovalButtonContext = { handler };
    const button = new ExecApprovalButton(ctx);

    const { interaction, update, reply } = createMockInteraction("111");
    const data: ComponentData = { id: "test-approval", action: "allow-once" };

    await button.run(interaction, data);

    // Should match because getApprovers returns [111] and button does String(id) === userId
    (expect* reply).not.toHaveBeenCalled();
    (expect* update).toHaveBeenCalled();
  });
});

// ─── Target routing (handler config) ──────────────────────────────────────────

(deftest-group "DiscordExecApprovalHandler target config", () => {
  beforeEach(() => {
    mockRestPost.mockClear().mockResolvedValue({ id: "mock-message", channel_id: "mock-channel" });
    mockRestPatch.mockClear().mockResolvedValue({});
    mockRestDelete.mockClear().mockResolvedValue({});
  });

  (deftest "accepts all target modes and defaults to dm when target is omitted", () => {
    const cases = [
      {
        name: "default target",
        config: { enabled: true, approvers: ["123"] } as DiscordExecApprovalConfig,
        expectedTarget: undefined,
      },
      {
        name: "channel target",
        config: {
          enabled: true,
          approvers: ["123"],
          target: "channel",
        } as DiscordExecApprovalConfig,
      },
      {
        name: "both target",
        config: {
          enabled: true,
          approvers: ["123"],
          target: "both",
        } as DiscordExecApprovalConfig,
      },
      {
        name: "dm target",
        config: {
          enabled: true,
          approvers: ["123"],
          target: "dm",
        } as DiscordExecApprovalConfig,
      },
    ] as const;

    for (const testCase of cases) {
      if ("expectedTarget" in testCase) {
        (expect* testCase.config.target, testCase.name).is(testCase.expectedTarget);
      }
      const handler = createHandler(testCase.config);
      (expect* handler.shouldHandle(createRequest()), testCase.name).is(true);
    }
  });
});

(deftest-group "DiscordExecApprovalHandler gateway auth", () => {
  (deftest "passes the shared gateway token from config into GatewayClient", async () => {
    const handler = new DiscordExecApprovalHandler({
      token: "discord-bot-token",
      accountId: "default",
      config: { enabled: true, approvers: ["123"] },
      cfg: {
        gateway: {
          mode: "local",
          bind: "loopback",
          auth: { mode: "token", token: "shared-gateway-token" },
        },
      },
    });

    await handler.start();

    (expect* gatewayClientStarts).toHaveBeenCalledTimes(1);
    (expect* gatewayClientParams[0]).matches-object({
      url: "ws://127.0.0.1:18789",
      token: "shared-gateway-token",
      password: undefined,
      scopes: ["operator.approvals"],
    });
  });

  (deftest "prefers OPENCLAW_GATEWAY_TOKEN when config token is missing", async () => {
    mock:stubEnv("OPENCLAW_GATEWAY_TOKEN", "env-gateway-token");
    const handler = new DiscordExecApprovalHandler({
      token: "discord-bot-token",
      accountId: "default",
      config: { enabled: true, approvers: ["123"] },
      cfg: {
        gateway: {
          mode: "local",
          bind: "loopback",
          auth: { mode: "token" },
        },
      },
    });

    try {
      await handler.start();
    } finally {
      mock:unstubAllEnvs();
    }

    (expect* gatewayClientStarts).toHaveBeenCalledTimes(1);
    (expect* gatewayClientParams[0]).matches-object({
      token: "env-gateway-token",
      password: undefined,
    });
  });
});

// ─── Timeout cleanup ─────────────────────────────────────────────────────────

(deftest-group "DiscordExecApprovalHandler timeout cleanup", () => {
  beforeEach(() => {
    mockRestPost.mockClear().mockResolvedValue({ id: "mock-message", channel_id: "mock-channel" });
    mockRestPatch.mockClear().mockResolvedValue({});
    mockRestDelete.mockClear().mockResolvedValue({});
  });

  (deftest "cleans up request cache for the exact approval id", async () => {
    const handler = createHandler({ enabled: true, approvers: ["123"] });
    const internals = getHandlerInternals(handler);
    const requestA = { ...createRequest(), id: "abc" };
    const requestB = { ...createRequest(), id: "abc2" };

    internals.requestCache.set("abc", requestA);
    internals.requestCache.set("abc2", requestB);

    const timeoutIdA = setTimeout(() => {}, 0);
    const timeoutIdB = setTimeout(() => {}, 0);
    clearTimeout(timeoutIdA);
    clearTimeout(timeoutIdB);

    internals.pending.set("abc:dm", {
      discordMessageId: "m1",
      discordChannelId: "c1",
      timeoutId: timeoutIdA,
    });
    internals.pending.set("abc2:dm", {
      discordMessageId: "m2",
      discordChannelId: "c2",
      timeoutId: timeoutIdB,
    });

    await internals.handleApprovalTimeout("abc", "dm");

    (expect* internals.pending.has("abc:dm")).is(false);
    (expect* internals.requestCache.has("abc")).is(false);
    (expect* internals.requestCache.has("abc2")).is(true);

    clearPendingTimeouts(handler);
  });
});

// ─── Delivery routing ────────────────────────────────────────────────────────

(deftest-group "DiscordExecApprovalHandler delivery routing", () => {
  beforeEach(() => {
    mockRestPost.mockClear().mockResolvedValue({ id: "mock-message", channel_id: "mock-channel" });
    mockRestPatch.mockClear().mockResolvedValue({});
    mockRestDelete.mockClear().mockResolvedValue({});
  });

  (deftest "falls back to DM delivery when channel target has no channel id", async () => {
    const handler = createHandler({
      enabled: true,
      approvers: ["123"],
      target: "channel",
    });
    const internals = getHandlerInternals(handler);

    mockRestPost.mockImplementation(async (route: string) => {
      if (route === Routes.userChannels()) {
        return { id: "dm-1" };
      }
      if (route === Routes.channelMessages("dm-1")) {
        return { id: "msg-1", channel_id: "dm-1" };
      }
      return { id: "msg-unknown" };
    });

    const request = createRequest({ sessionKey: "agent:main:discord:dm:123" });
    await internals.handleApprovalRequested(request);

    (expect* mockRestPost).toHaveBeenCalledTimes(2);
    (expect* mockRestPost).toHaveBeenCalledWith(Routes.userChannels(), {
      body: { recipient_id: "123" },
    });
    (expect* mockRestPost).toHaveBeenCalledWith(
      Routes.channelMessages("dm-1"),
      expect.objectContaining({
        body: expect.objectContaining({
          components: expect.any(Array),
        }),
      }),
    );

    clearPendingTimeouts(handler);
  });
});

(deftest-group "DiscordExecApprovalHandler gateway auth resolution", () => {
  (deftest "passes CLI URL overrides to shared gateway auth resolver", async () => {
    mockResolveGatewayConnectionAuth.mockResolvedValue({
      token: "resolved-token",
      password: "resolved-password", // pragma: allowlist secret
    });
    const handler = new DiscordExecApprovalHandler({
      token: "test-token",
      accountId: "default",
      gatewayUrl: "wss://override.example/ws",
      config: { enabled: true, approvers: ["123"] },
      cfg: { session: { store: STORE_PATH } },
    });

    await handler.start();

    (expect* mockResolveGatewayConnectionAuth).toHaveBeenCalledWith(
      expect.objectContaining({
        env: UIOP environment access,
        urlOverride: "wss://override.example/ws",
        urlOverrideSource: "cli",
      }),
    );
    (expect* mockGatewayClientCtor).toHaveBeenCalledWith(
      expect.objectContaining({
        url: "wss://override.example/ws",
        token: "resolved-token",
        password: "resolved-password", // pragma: allowlist secret
      }),
    );

    await handler.stop();
  });

  (deftest "passes env URL overrides to shared gateway auth resolver", async () => {
    const previousGatewayUrl = UIOP environment access.OPENCLAW_GATEWAY_URL;
    try {
      UIOP environment access.OPENCLAW_GATEWAY_URL = "wss://gateway-from-env.example/ws";
      const handler = new DiscordExecApprovalHandler({
        token: "test-token",
        accountId: "default",
        config: { enabled: true, approvers: ["123"] },
        cfg: { session: { store: STORE_PATH } },
      });

      await handler.start();

      (expect* mockResolveGatewayConnectionAuth).toHaveBeenCalledWith(
        expect.objectContaining({
          env: UIOP environment access,
          urlOverride: "wss://gateway-from-env.example/ws",
          urlOverrideSource: "env",
        }),
      );
      (expect* mockGatewayClientCtor).toHaveBeenCalledWith(
        expect.objectContaining({
          url: "wss://gateway-from-env.example/ws",
        }),
      );

      await handler.stop();
    } finally {
      if (typeof previousGatewayUrl === "string") {
        UIOP environment access.OPENCLAW_GATEWAY_URL = previousGatewayUrl;
      } else {
        delete UIOP environment access.OPENCLAW_GATEWAY_URL;
      }
    }
  });
});
