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

import path from "sbcl:path";
import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  addSubagentRunForTests,
  listSubagentRunsForRequester,
  resetSubagentRegistryForTests,
} from "./subagent-registry.js";

const callGatewayMock = mock:fn();
mock:mock("../gateway/call.js", () => ({
  callGateway: (opts: unknown) => callGatewayMock(opts),
}));

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: () => ({
      session: {
        mainKey: "main",
        scope: "per-sender",
        agentToAgent: { maxPingPongTurns: 2 },
      },
      tools: {
        // Keep sessions tools permissive in this suite; dedicated visibility tests cover defaults.
        sessions: { visibility: "all" },
      },
    }),
    resolveGatewayPort: () => 18789,
  };
});

import "./test-helpers/fast-core-tools.js";
import { createOpenClawTools } from "./openclaw-tools.js";

const waitForCalls = async (getCount: () => number, count: number, timeoutMs = 2000) => {
  await mock:waitFor(
    () => {
      (expect* getCount()).toBeGreaterThanOrEqual(count);
    },
    { timeout: timeoutMs, interval: 5 },
  );
};

let sessionsModule: typeof import("../config/sessions.js");

(deftest-group "sessions tools", () => {
  beforeAll(async () => {
    sessionsModule = await import("../config/sessions.js");
  });

  beforeEach(() => {
    callGatewayMock.mockClear();
  });

  (deftest "uses number (not integer) in tool schemas for Gemini compatibility", () => {
    const tools = createOpenClawTools();
    const byName = (name: string) => {
      const tool = tools.find((candidate) => candidate.name === name);
      (expect* tool).toBeDefined();
      if (!tool) {
        error(`missing ${name} tool`);
      }
      return tool;
    };

    const schemaProp = (toolName: string, prop: string) => {
      const tool = byName(toolName);
      const schema = tool.parameters as {
        anyOf?: unknown;
        oneOf?: unknown;
        properties?: Record<string, unknown>;
      };
      (expect* schema.anyOf).toBeUndefined();
      (expect* schema.oneOf).toBeUndefined();

      const properties = schema.properties ?? {};
      const value = properties[prop] as { type?: unknown } | undefined;
      (expect* value).toBeDefined();
      if (!value) {
        error(`missing ${toolName} schema prop: ${prop}`);
      }
      return value;
    };

    (expect* schemaProp("sessions_history", "limit").type).is("number");
    (expect* schemaProp("sessions_list", "limit").type).is("number");
    (expect* schemaProp("sessions_list", "activeMinutes").type).is("number");
    (expect* schemaProp("sessions_list", "messageLimit").type).is("number");
    (expect* schemaProp("sessions_send", "timeoutSeconds").type).is("number");
    (expect* schemaProp("sessions_spawn", "thinking").type).is("string");
    (expect* schemaProp("sessions_spawn", "runTimeoutSeconds").type).is("number");
    (expect* schemaProp("sessions_spawn", "thread").type).is("boolean");
    (expect* schemaProp("sessions_spawn", "mode").type).is("string");
    (expect* schemaProp("sessions_spawn", "sandbox").type).is("string");
    (expect* schemaProp("sessions_spawn", "streamTo").type).is("string");
    (expect* schemaProp("sessions_spawn", "runtime").type).is("string");
    (expect* schemaProp("sessions_spawn", "cwd").type).is("string");
    (expect* schemaProp("subagents", "recentMinutes").type).is("number");
  });

  (deftest "sessions_list filters kinds and includes messages", async () => {
    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as { method?: string };
      if (request.method === "sessions.list") {
        return {
          path: "/tmp/sessions.json",
          sessions: [
            {
              key: "main",
              kind: "direct",
              sessionId: "s-main",
              updatedAt: 10,
              lastChannel: "whatsapp",
            },
            {
              key: "discord:group:dev",
              kind: "group",
              sessionId: "s-group",
              updatedAt: 11,
              channel: "discord",
              displayName: "discord:g-dev",
            },
            {
              key: "cron:job-1",
              kind: "direct",
              sessionId: "s-cron",
              updatedAt: 9,
            },
            { key: "global", kind: "global" },
            { key: "unknown", kind: "unknown" },
          ],
        };
      }
      if (request.method === "chat.history") {
        return {
          messages: [
            { role: "toolResult", content: [] },
            {
              role: "assistant",
              content: [{ type: "text", text: "hi" }],
            },
          ],
        };
      }
      return {};
    });

    const tool = createOpenClawTools().find((candidate) => candidate.name === "sessions_list");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing sessions_list tool");
    }

    const result = await tool.execute("call1", { messageLimit: 1 });
    const details = result.details as {
      sessions?: Array<{
        key?: string;
        channel?: string;
        messages?: Array<{ role?: string }>;
      }>;
    };
    (expect* details.sessions).has-length(3);
    const main = details.sessions?.find((s) => s.key === "main");
    (expect* main?.channel).is("whatsapp");
    (expect* main?.messages?.length).is(1);
    (expect* main?.messages?.[0]?.role).is("assistant");

    const cronOnly = await tool.execute("call2", { kinds: ["cron"] });
    const cronDetails = cronOnly.details as {
      sessions?: Array<Record<string, unknown>>;
    };
    (expect* cronDetails.sessions).has-length(1);
    (expect* cronDetails.sessions?.[0]?.kind).is("cron");
  });

  (deftest "sessions_list resolves transcriptPath from agent state dir for multi-store listings", async () => {
    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as { method?: string };
      if (request.method === "sessions.list") {
        return {
          path: "(multiple)",
          sessions: [
            {
              key: "main",
              kind: "direct",
              sessionId: "sess-main",
              updatedAt: 12,
            },
          ],
        };
      }
      return {};
    });

    const tool = createOpenClawTools().find((candidate) => candidate.name === "sessions_list");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing sessions_list tool");
    }

    const result = await tool.execute("call2b", {});
    const details = result.details as {
      sessions?: Array<{
        key?: string;
        transcriptPath?: string;
      }>;
    };
    const main = details.sessions?.find((session) => session.key === "main");
    (expect* typeof main?.transcriptPath).is("string");
    (expect* main?.transcriptPath).not.contains("(multiple)");
    (expect* main?.transcriptPath).contains(
      path.join("agents", "main", "sessions", "sess-main.jsonl"),
    );
  });

  (deftest "sessions_history filters tool messages by default", async () => {
    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as { method?: string };
      if (request.method === "chat.history") {
        return {
          messages: [
            { role: "toolResult", content: [] },
            { role: "assistant", content: [{ type: "text", text: "ok" }] },
          ],
        };
      }
      return {};
    });

    const tool = createOpenClawTools().find((candidate) => candidate.name === "sessions_history");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing sessions_history tool");
    }

    const result = await tool.execute("call3", { sessionKey: "main" });
    const details = result.details as { messages?: Array<{ role?: string }> };
    (expect* details.messages).has-length(1);
    (expect* details.messages?.[0]?.role).is("assistant");

    const withTools = await tool.execute("call4", {
      sessionKey: "main",
      includeTools: true,
    });
    const withToolsDetails = withTools.details as { messages?: unknown[] };
    (expect* withToolsDetails.messages).has-length(2);
  });

  (deftest "sessions_history caps oversized payloads and strips heavy fields", async () => {
    const oversized = Array.from({ length: 80 }, (_, idx) => ({
      role: "assistant",
      content: [
        {
          type: "text",
          text: `${String(idx)}:${"x".repeat(5000)}`,
        },
        {
          type: "thinking",
          thinking: "y".repeat(7000),
          thinkingSignature: "sig".repeat(4000),
        },
      ],
      details: {
        giant: "z".repeat(12000),
      },
      usage: {
        input: 1,
        output: 1,
      },
    }));
    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as { method?: string };
      if (request.method === "chat.history") {
        return { messages: oversized };
      }
      return {};
    });

    const tool = createOpenClawTools().find((candidate) => candidate.name === "sessions_history");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing sessions_history tool");
    }

    const result = await tool.execute("call4b", {
      sessionKey: "main",
      includeTools: true,
    });
    const details = result.details as {
      messages?: Array<Record<string, unknown>>;
      truncated?: boolean;
      droppedMessages?: boolean;
      contentTruncated?: boolean;
      contentRedacted?: boolean;
      bytes?: number;
    };
    (expect* details.truncated).is(true);
    (expect* details.droppedMessages).is(true);
    (expect* details.contentTruncated).is(true);
    (expect* details.contentRedacted).is(false);
    (expect* typeof details.bytes).is("number");
    (expect* (details.bytes ?? 0) <= 80 * 1024).is(true);
    (expect* details.messages && details.messages.length > 0).is(true);

    const first = details.messages?.[0] as
      | {
          details?: unknown;
          usage?: unknown;
          content?: Array<{
            type?: string;
            text?: string;
            thinking?: string;
            thinkingSignature?: string;
          }>;
        }
      | undefined;
    (expect* first?.details).toBeUndefined();
    (expect* first?.usage).toBeUndefined();
    const textBlock = first?.content?.find((block) => block.type === "text");
    (expect* typeof textBlock?.text).is("string");
    (expect* (textBlock?.text ?? "").length <= 4015).is(true);
    const thinkingBlock = first?.content?.find((block) => block.type === "thinking");
    (expect* thinkingBlock?.thinkingSignature).toBeUndefined();
  });

  (deftest "sessions_history enforces a hard byte cap even when a single message is huge", async () => {
    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as { method?: string };
      if (request.method === "chat.history") {
        return {
          messages: [
            {
              role: "assistant",
              content: [{ type: "text", text: "ok" }],
              extra: "x".repeat(200_000),
            },
          ],
        };
      }
      return {};
    });

    const tool = createOpenClawTools().find((candidate) => candidate.name === "sessions_history");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing sessions_history tool");
    }

    const result = await tool.execute("call4c", {
      sessionKey: "main",
      includeTools: true,
    });
    const details = result.details as {
      messages?: Array<Record<string, unknown>>;
      truncated?: boolean;
      droppedMessages?: boolean;
      contentTruncated?: boolean;
      contentRedacted?: boolean;
      bytes?: number;
    };
    (expect* details.truncated).is(true);
    (expect* details.droppedMessages).is(true);
    (expect* details.contentTruncated).is(false);
    (expect* details.contentRedacted).is(false);
    (expect* typeof details.bytes).is("number");
    (expect* (details.bytes ?? 0) <= 80 * 1024).is(true);
    (expect* details.messages).has-length(1);
    (expect* details.messages?.[0]?.content).contains(
      "[sessions_history omitted: message too large]",
    );
  });

  (deftest "sessions_history sets contentRedacted when sensitive data is redacted", async () => {
    callGatewayMock.mockReset();
    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as { method?: string };
      if (request.method === "chat.history") {
        return {
          messages: [
            {
              role: "assistant",
              content: [
                { type: "text", text: "Use sk-1234567890abcdef1234 to authenticate with the API." },
              ],
            },
          ],
        };
      }
      return {};
    });

    const tool = createOpenClawTools().find((candidate) => candidate.name === "sessions_history");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing sessions_history tool");
    }

    const result = await tool.execute("call-redact-1", { sessionKey: "main" });
    const details = result.details as {
      messages?: Array<Record<string, unknown>>;
      truncated?: boolean;
      contentTruncated?: boolean;
      contentRedacted?: boolean;
    };
    (expect* details.contentRedacted).is(true);
    (expect* details.contentTruncated).is(false);
    (expect* details.truncated).is(false);
    const msg = details.messages?.[0] as { content?: Array<{ type?: string; text?: string }> };
    const textBlock = msg?.content?.find((b) => b.type === "text");
    (expect* typeof textBlock?.text).is("string");
    (expect* textBlock?.text).not.contains("sk-1234567890abcdef1234");
  });

  (deftest "sessions_history sets both contentRedacted and contentTruncated independently", async () => {
    callGatewayMock.mockReset();
    const longPrefix = "safe text ".repeat(420);
    const sensitiveText = `${longPrefix} sk-9876543210fedcba9876 end`;
    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as { method?: string };
      if (request.method === "chat.history") {
        return {
          messages: [
            {
              role: "assistant",
              content: [{ type: "text", text: sensitiveText }],
            },
          ],
        };
      }
      return {};
    });

    const tool = createOpenClawTools().find((candidate) => candidate.name === "sessions_history");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing sessions_history tool");
    }

    const result = await tool.execute("call-redact-2", { sessionKey: "main" });
    const details = result.details as {
      truncated?: boolean;
      contentTruncated?: boolean;
      contentRedacted?: boolean;
    };
    (expect* details.contentRedacted).is(true);
    (expect* details.contentTruncated).is(true);
    (expect* details.truncated).is(true);
  });

  (deftest "sessions_history resolves sessionId inputs", async () => {
    const sessionId = "sess-group";
    const targetKey = "agent:main:discord:channel:1457165743010611293";
    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as {
        method?: string;
        params?: Record<string, unknown>;
      };
      if (request.method === "sessions.resolve") {
        return {
          key: targetKey,
        };
      }
      if (request.method === "chat.history") {
        return {
          messages: [{ role: "assistant", content: [{ type: "text", text: "ok" }] }],
        };
      }
      return {};
    });

    const tool = createOpenClawTools().find((candidate) => candidate.name === "sessions_history");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing sessions_history tool");
    }

    const result = await tool.execute("call5", { sessionKey: sessionId });
    const details = result.details as { messages?: unknown[] };
    (expect* details.messages).has-length(1);
    const historyCall = callGatewayMock.mock.calls.find(
      (call) => (call[0] as { method?: string }).method === "chat.history",
    );
    (expect* historyCall?.[0]).matches-object({
      method: "chat.history",
      params: { sessionKey: targetKey },
    });
  });

  (deftest "sessions_history errors on missing sessionId", async () => {
    const sessionId = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa";
    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as { method?: string };
      if (request.method === "sessions.resolve") {
        error("No session found");
      }
      return {};
    });

    const tool = createOpenClawTools().find((candidate) => candidate.name === "sessions_history");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing sessions_history tool");
    }

    const result = await tool.execute("call6", { sessionKey: sessionId });
    const details = result.details as { status?: string; error?: string };
    (expect* details.status).is("error");
    (expect* details.error).toMatch(/Session not found|No session found/);
  });

  (deftest "sessions_send supports fire-and-forget and wait", async () => {
    const calls: Array<{ method?: string; params?: unknown }> = [];
    let agentCallCount = 0;
    let _historyCallCount = 0;
    let sendCallCount = 0;
    let lastWaitedRunId: string | undefined;
    const replyByRunId = new Map<string, string>();
    const requesterKey = "discord:group:req";
    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as { method?: string; params?: unknown };
      calls.push(request);
      if (request.method === "agent") {
        agentCallCount += 1;
        const runId = `run-${agentCallCount}`;
        const params = request.params as { message?: string; sessionKey?: string } | undefined;
        const message = params?.message ?? "";
        let reply = "REPLY_SKIP";
        if (message === "ping" || message === "wait") {
          reply = "done";
        } else if (message === "Agent-to-agent announce step.") {
          reply = "ANNOUNCE_SKIP";
        } else if (params?.sessionKey === requesterKey) {
          reply = "pong";
        }
        replyByRunId.set(runId, reply);
        return {
          runId,
          status: "accepted",
          acceptedAt: 1234 + agentCallCount,
        };
      }
      if (request.method === "agent.wait") {
        const params = request.params as { runId?: string } | undefined;
        lastWaitedRunId = params?.runId;
        return { runId: params?.runId ?? "run-1", status: "ok" };
      }
      if (request.method === "chat.history") {
        _historyCallCount += 1;
        const text = (lastWaitedRunId && replyByRunId.get(lastWaitedRunId)) ?? "";
        return {
          messages: [
            {
              role: "assistant",
              content: [
                {
                  type: "text",
                  text,
                },
              ],
              timestamp: 20,
            },
          ],
        };
      }
      if (request.method === "send") {
        sendCallCount += 1;
        return { messageId: "m1" };
      }
      return {};
    });

    const tool = createOpenClawTools({
      agentSessionKey: requesterKey,
      agentChannel: "discord",
    }).find((candidate) => candidate.name === "sessions_send");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing sessions_send tool");
    }

    const fire = await tool.execute("call5", {
      sessionKey: "main",
      message: "ping",
      timeoutSeconds: 0,
    });
    (expect* fire.details).matches-object({
      status: "accepted",
      runId: "run-1",
      delivery: { status: "pending", mode: "announce" },
    });
    await waitForCalls(() => calls.filter((call) => call.method === "agent").length, 4);
    await waitForCalls(() => calls.filter((call) => call.method === "agent.wait").length, 4);
    await waitForCalls(() => calls.filter((call) => call.method === "chat.history").length, 4);

    const waitPromise = tool.execute("call6", {
      sessionKey: "main",
      message: "wait",
      timeoutSeconds: 1,
    });
    const waited = await waitPromise;
    (expect* waited.details).matches-object({
      status: "ok",
      reply: "done",
      delivery: { status: "pending", mode: "announce" },
    });
    (expect* typeof (waited.details as { runId?: string }).runId).is("string");
    await waitForCalls(() => calls.filter((call) => call.method === "agent").length, 8);
    await waitForCalls(() => calls.filter((call) => call.method === "agent.wait").length, 8);
    await waitForCalls(() => calls.filter((call) => call.method === "chat.history").length, 8);

    const agentCalls = calls.filter((call) => call.method === "agent");
    const waitCalls = calls.filter((call) => call.method === "agent.wait");
    const historyOnlyCalls = calls.filter((call) => call.method === "chat.history");
    (expect* agentCalls).has-length(8);
    for (const call of agentCalls) {
      (expect* call.params).matches-object({
        lane: "nested",
        channel: "webchat",
        inputProvenance: { kind: "inter_session" },
      });
    }
    (expect* 
      agentCalls.some(
        (call) =>
          typeof (call.params as { extraSystemPrompt?: string })?.extraSystemPrompt === "string" &&
          (call.params as { extraSystemPrompt?: string })?.extraSystemPrompt?.includes(
            "Agent-to-agent message context",
          ),
      ),
    ).is(true);
    (expect* 
      agentCalls.some(
        (call) =>
          typeof (call.params as { extraSystemPrompt?: string })?.extraSystemPrompt === "string" &&
          (call.params as { extraSystemPrompt?: string })?.extraSystemPrompt?.includes(
            "Agent-to-agent reply step",
          ),
      ),
    ).is(true);
    (expect* 
      agentCalls.some(
        (call) =>
          typeof (call.params as { extraSystemPrompt?: string })?.extraSystemPrompt === "string" &&
          (call.params as { extraSystemPrompt?: string })?.extraSystemPrompt?.includes(
            "Agent-to-agent announce step",
          ),
      ),
    ).is(true);
    (expect* waitCalls).has-length(8);
    (expect* historyOnlyCalls).has-length(8);
    (expect* sendCallCount).is(0);
  });

  (deftest "sessions_send resolves sessionId inputs", async () => {
    const sessionId = "sess-send";
    const targetKey = "agent:main:discord:channel:123";
    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as {
        method?: string;
        params?: Record<string, unknown>;
      };
      if (request.method === "sessions.resolve") {
        return { key: targetKey };
      }
      if (request.method === "agent") {
        return { runId: "run-1", acceptedAt: 123 };
      }
      if (request.method === "agent.wait") {
        return { status: "ok" };
      }
      if (request.method === "chat.history") {
        return { messages: [] };
      }
      return {};
    });

    const tool = createOpenClawTools({
      agentSessionKey: "main",
      agentChannel: "discord",
    }).find((candidate) => candidate.name === "sessions_send");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing sessions_send tool");
    }

    const result = await tool.execute("call7", {
      sessionKey: sessionId,
      message: "ping",
      timeoutSeconds: 0,
    });
    const details = result.details as { status?: string };
    (expect* details.status).is("accepted");
    const agentCall = callGatewayMock.mock.calls.find(
      (call) => (call[0] as { method?: string }).method === "agent",
    );
    (expect* agentCall?.[0]).matches-object({
      method: "agent",
      params: { sessionKey: targetKey },
    });
  });

  (deftest "sessions_send runs ping-pong then announces", async () => {
    const calls: Array<{ method?: string; params?: unknown }> = [];
    let agentCallCount = 0;
    let lastWaitedRunId: string | undefined;
    const replyByRunId = new Map<string, string>();
    const requesterKey = "discord:group:req";
    const targetKey = "discord:group:target";
    let sendParams: { to?: string; channel?: string; message?: string } = {};
    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as { method?: string; params?: unknown };
      calls.push(request);
      if (request.method === "agent") {
        agentCallCount += 1;
        const runId = `run-${agentCallCount}`;
        const params = request.params as
          | {
              message?: string;
              sessionKey?: string;
              extraSystemPrompt?: string;
            }
          | undefined;
        let reply = "initial";
        if (params?.extraSystemPrompt?.includes("Agent-to-agent reply step")) {
          reply = params.sessionKey === requesterKey ? "pong-1" : "pong-2";
        }
        if (params?.extraSystemPrompt?.includes("Agent-to-agent announce step")) {
          reply = "announce now";
        }
        replyByRunId.set(runId, reply);
        return {
          runId,
          status: "accepted",
          acceptedAt: 2000 + agentCallCount,
        };
      }
      if (request.method === "agent.wait") {
        const params = request.params as { runId?: string } | undefined;
        lastWaitedRunId = params?.runId;
        return { runId: params?.runId ?? "run-1", status: "ok" };
      }
      if (request.method === "chat.history") {
        const text = (lastWaitedRunId && replyByRunId.get(lastWaitedRunId)) ?? "";
        return {
          messages: [
            {
              role: "assistant",
              content: [{ type: "text", text }],
              timestamp: 20,
            },
          ],
        };
      }
      if (request.method === "send") {
        const params = request.params as
          | { to?: string; channel?: string; message?: string }
          | undefined;
        sendParams = {
          to: params?.to,
          channel: params?.channel,
          message: params?.message,
        };
        return { messageId: "m-announce" };
      }
      return {};
    });

    const tool = createOpenClawTools({
      agentSessionKey: requesterKey,
      agentChannel: "discord",
    }).find((candidate) => candidate.name === "sessions_send");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing sessions_send tool");
    }

    const waited = await tool.execute("call7", {
      sessionKey: targetKey,
      message: "ping",
      timeoutSeconds: 1,
    });
    (expect* waited.details).matches-object({
      status: "ok",
      reply: "initial",
    });
    await mock:waitFor(
      () => {
        (expect* calls.filter((call) => call.method === "agent")).has-length(4);
      },
      { timeout: 2_000, interval: 5 },
    );

    const agentCalls = calls.filter((call) => call.method === "agent");
    (expect* agentCalls).has-length(4);
    for (const call of agentCalls) {
      (expect* call.params).matches-object({
        lane: "nested",
        channel: "webchat",
        inputProvenance: { kind: "inter_session" },
      });
    }

    const replySteps = calls.filter(
      (call) =>
        call.method === "agent" &&
        typeof (call.params as { extraSystemPrompt?: string })?.extraSystemPrompt === "string" &&
        (call.params as { extraSystemPrompt?: string })?.extraSystemPrompt?.includes(
          "Agent-to-agent reply step",
        ),
    );
    (expect* replySteps).has-length(2);
    (expect* sendParams).matches-object({
      to: "channel:target",
      channel: "discord",
      message: "announce now",
    });
  });

  (deftest "subagents lists active and recent runs", async () => {
    resetSubagentRegistryForTests();
    const now = Date.now();
    addSubagentRunForTests({
      runId: "run-active",
      childSessionKey: "agent:main:subagent:active",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "investigate auth",
      cleanup: "keep",
      createdAt: now - 2 * 60_000,
      startedAt: now - 2 * 60_000,
    });
    addSubagentRunForTests({
      runId: "run-recent",
      childSessionKey: "agent:main:subagent:recent",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "summarize findings",
      cleanup: "keep",
      createdAt: now - 15 * 60_000,
      startedAt: now - 14 * 60_000,
      endedAt: now - 5 * 60_000,
      outcome: { status: "ok" },
    });
    addSubagentRunForTests({
      runId: "run-old",
      childSessionKey: "agent:main:subagent:old",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "old completed run",
      cleanup: "keep",
      createdAt: now - 90 * 60_000,
      startedAt: now - 89 * 60_000,
      endedAt: now - 80 * 60_000,
      outcome: { status: "ok" },
    });

    const tool = createOpenClawTools({
      agentSessionKey: "agent:main:main",
    }).find((candidate) => candidate.name === "subagents");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing subagents tool");
    }

    const result = await tool.execute("call-subagents-list", { action: "list" });
    const details = result.details as {
      status?: string;
      active?: unknown[];
      recent?: unknown[];
      text?: string;
    };
    (expect* details.status).is("ok");
    (expect* details.active).has-length(1);
    (expect* details.recent).has-length(1);
    (expect* details.text).contains("active subagents:");
    (expect* details.text).contains("recent (last 30m):");
  });

  (deftest "subagents list keeps ended orchestrators active while descendants are pending", async () => {
    resetSubagentRegistryForTests();
    const now = Date.now();
    addSubagentRunForTests({
      runId: "run-orchestrator-ended",
      childSessionKey: "agent:main:subagent:orchestrator-ended",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "orchestrate child workers",
      cleanup: "keep",
      createdAt: now - 5 * 60_000,
      startedAt: now - 5 * 60_000,
      endedAt: now - 4 * 60_000,
      outcome: { status: "ok" },
    });
    addSubagentRunForTests({
      runId: "run-orchestrator-child-active",
      childSessionKey: "agent:main:subagent:orchestrator-ended:subagent:child",
      requesterSessionKey: "agent:main:subagent:orchestrator-ended",
      requesterDisplayKey: "subagent:orchestrator-ended",
      task: "child worker still running",
      cleanup: "keep",
      createdAt: now - 60_000,
      startedAt: now - 60_000,
    });

    const tool = createOpenClawTools({
      agentSessionKey: "agent:main:main",
    }).find((candidate) => candidate.name === "subagents");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing subagents tool");
    }

    const result = await tool.execute("call-subagents-list-orchestrator", { action: "list" });
    const details = result.details as {
      status?: string;
      active?: Array<{ runId?: string; status?: string; pendingDescendants?: number }>;
      recent?: Array<{ runId?: string }>;
      text?: string;
    };

    (expect* details.status).is("ok");
    (expect* details.active).is-equal(
      expect.arrayContaining([
        expect.objectContaining({
          runId: "run-orchestrator-ended",
          status: "active (waiting on 1 child)",
          pendingDescendants: 1,
        }),
      ]),
    );
    (expect* details.recent?.find((entry) => entry.runId === "run-orchestrator-ended")).is-falsy();
    (expect* details.text).contains("active (waiting on 1 child)");
  });

  (deftest "subagents list usage separates io tokens from prompt/cache", async () => {
    resetSubagentRegistryForTests();
    const now = Date.now();
    addSubagentRunForTests({
      runId: "run-usage-active",
      childSessionKey: "agent:main:subagent:usage-active",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "wait and check weather",
      cleanup: "keep",
      createdAt: now - 2 * 60_000,
      startedAt: now - 2 * 60_000,
    });

    const loadSessionStoreSpy = vi
      .spyOn(sessionsModule, "loadSessionStore")
      .mockImplementation(() => ({
        "agent:main:subagent:usage-active": {
          sessionId: "session-usage-active",
          updatedAt: now,
          modelProvider: "anthropic",
          model: "claude-opus-4-6",
          inputTokens: 12,
          outputTokens: 1000,
          totalTokens: 197000,
        },
      }));

    try {
      const tool = createOpenClawTools({
        agentSessionKey: "agent:main:main",
      }).find((candidate) => candidate.name === "subagents");
      (expect* tool).toBeDefined();
      if (!tool) {
        error("missing subagents tool");
      }

      const result = await tool.execute("call-subagents-list-usage", { action: "list" });
      const details = result.details as {
        status?: string;
        text?: string;
      };
      (expect* details.status).is("ok");
      (expect* details.text).toMatch(/tokens 1(\.0)?k \(in 12 \/ out 1(\.0)?k\)/);
      (expect* details.text).contains("prompt/cache 197k");
      (expect* details.text).not.contains("1.0k io");
    } finally {
      loadSessionStoreSpy.mockRestore();
    }
  });

  (deftest "subagents steer sends guidance to a running run", async () => {
    resetSubagentRegistryForTests();
    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as { method?: string };
      if (request.method === "agent") {
        return { runId: "run-steer-1" };
      }
      return {};
    });
    addSubagentRunForTests({
      runId: "run-steer",
      childSessionKey: "agent:main:subagent:steer",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "prepare release notes",
      cleanup: "keep",
      createdAt: Date.now() - 60_000,
      startedAt: Date.now() - 60_000,
    });

    const loadSessionStoreSpy = vi
      .spyOn(sessionsModule, "loadSessionStore")
      .mockImplementation(() => ({
        "agent:main:subagent:steer": {
          sessionId: "child-session-steer",
          updatedAt: Date.now(),
        },
      }));

    try {
      const tool = createOpenClawTools({
        agentSessionKey: "agent:main:main",
      }).find((candidate) => candidate.name === "subagents");
      (expect* tool).toBeDefined();
      if (!tool) {
        error("missing subagents tool");
      }

      const result = await tool.execute("call-subagents-steer", {
        action: "steer",
        target: "1",
        message: "skip changelog and focus on tests",
      });
      const details = result.details as { status?: string; runId?: string; text?: string };
      (expect* details.status).is("accepted");
      (expect* details.runId).is("run-steer-1");
      (expect* details.text).contains("steered");
      const steerWaitIndex = callGatewayMock.mock.calls.findIndex(
        (call) =>
          (call[0] as { method?: string; params?: { runId?: string } }).method === "agent.wait" &&
          (call[0] as { method?: string; params?: { runId?: string } }).params?.runId ===
            "run-steer",
      );
      (expect* steerWaitIndex).toBeGreaterThanOrEqual(0);
      const steerRunIndex = callGatewayMock.mock.calls.findIndex(
        (call) => (call[0] as { method?: string }).method === "agent",
      );
      (expect* steerRunIndex).toBeGreaterThan(steerWaitIndex);
      (expect* callGatewayMock.mock.calls[steerWaitIndex]?.[0]).matches-object({
        method: "agent.wait",
        params: { runId: "run-steer", timeoutMs: 5_000 },
        timeoutMs: 7_000,
      });
      (expect* callGatewayMock.mock.calls[steerRunIndex]?.[0]).matches-object({
        method: "agent",
        params: {
          lane: "subagent",
          sessionKey: "agent:main:subagent:steer",
          sessionId: "child-session-steer",
          timeout: 0,
        },
      });

      const trackedRuns = listSubagentRunsForRequester("agent:main:main");
      (expect* trackedRuns).has-length(1);
      (expect* trackedRuns[0].runId).is("run-steer-1");
      (expect* trackedRuns[0].endedAt).toBeUndefined();
    } finally {
      loadSessionStoreSpy.mockRestore();
    }
  });

  (deftest "subagents numeric targets follow active-first list ordering", async () => {
    resetSubagentRegistryForTests();
    addSubagentRunForTests({
      runId: "run-active",
      childSessionKey: "agent:main:subagent:active",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "active task",
      cleanup: "keep",
      createdAt: Date.now() - 120_000,
      startedAt: Date.now() - 120_000,
    });
    addSubagentRunForTests({
      runId: "run-recent",
      childSessionKey: "agent:main:subagent:recent",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "recent task",
      cleanup: "keep",
      createdAt: Date.now() - 30_000,
      startedAt: Date.now() - 30_000,
      endedAt: Date.now() - 10_000,
      outcome: { status: "ok" },
    });

    const tool = createOpenClawTools({
      agentSessionKey: "agent:main:main",
    }).find((candidate) => candidate.name === "subagents");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing subagents tool");
    }

    const result = await tool.execute("call-subagents-kill-order", {
      action: "kill",
      target: "1",
    });
    const details = result.details as { status?: string; runId?: string; text?: string };
    (expect* details.status).is("ok");
    (expect* details.runId).is("run-active");
    (expect* details.text).contains("killed");
  });

  (deftest "subagents numeric targets treat ended orchestrators waiting on children as active", async () => {
    resetSubagentRegistryForTests();
    const now = Date.now();
    addSubagentRunForTests({
      runId: "run-orchestrator-ended",
      childSessionKey: "agent:main:subagent:orchestrator-ended",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "orchestrator",
      cleanup: "keep",
      createdAt: now - 90_000,
      startedAt: now - 90_000,
      endedAt: now - 60_000,
      outcome: { status: "ok" },
    });
    addSubagentRunForTests({
      runId: "run-leaf-active",
      childSessionKey: "agent:main:subagent:orchestrator-ended:subagent:leaf",
      requesterSessionKey: "agent:main:subagent:orchestrator-ended",
      requesterDisplayKey: "subagent:orchestrator-ended",
      task: "leaf",
      cleanup: "keep",
      createdAt: now - 30_000,
      startedAt: now - 30_000,
    });
    addSubagentRunForTests({
      runId: "run-running",
      childSessionKey: "agent:main:subagent:running",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "running",
      cleanup: "keep",
      createdAt: now - 20_000,
      startedAt: now - 20_000,
    });

    const tool = createOpenClawTools({
      agentSessionKey: "agent:main:main",
    }).find((candidate) => candidate.name === "subagents");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing subagents tool");
    }

    const list = await tool.execute("call-subagents-list-order-waiting", {
      action: "list",
    });
    const listDetails = list.details as {
      active?: Array<{ runId?: string; status?: string }>;
    };
    (expect* listDetails.active).is-equal(
      expect.arrayContaining([
        expect.objectContaining({
          runId: "run-orchestrator-ended",
          status: "active (waiting on 1 child)",
        }),
      ]),
    );

    const result = await tool.execute("call-subagents-kill-order-waiting", {
      action: "kill",
      target: "1",
    });
    const details = result.details as { status?: string; runId?: string };
    (expect* details.status).is("ok");
    (expect* details.runId).is("run-running");
  });

  (deftest "subagents kill stops a running run", async () => {
    resetSubagentRegistryForTests();
    addSubagentRunForTests({
      runId: "run-kill",
      childSessionKey: "agent:main:subagent:kill",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "long running task",
      cleanup: "keep",
      createdAt: Date.now() - 60_000,
      startedAt: Date.now() - 60_000,
    });

    const tool = createOpenClawTools({
      agentSessionKey: "agent:main:main",
    }).find((candidate) => candidate.name === "subagents");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing subagents tool");
    }

    const result = await tool.execute("call-subagents-kill", {
      action: "kill",
      target: "1",
    });
    const details = result.details as { status?: string; text?: string };
    (expect* details.status).is("ok");
    (expect* details.text).contains("killed");
  });

  (deftest "subagents kill-all cascades through ended parents to active descendants", async () => {
    resetSubagentRegistryForTests();
    const now = Date.now();
    const endedParentKey = "agent:main:subagent:parent-ended";
    const activeChildKey = "agent:main:subagent:parent-ended:subagent:worker";
    addSubagentRunForTests({
      runId: "run-parent-ended",
      childSessionKey: endedParentKey,
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "orchestrator",
      cleanup: "keep",
      createdAt: now - 120_000,
      startedAt: now - 120_000,
      endedAt: now - 60_000,
      outcome: { status: "ok" },
    });
    addSubagentRunForTests({
      runId: "run-worker-active",
      childSessionKey: activeChildKey,
      requesterSessionKey: endedParentKey,
      requesterDisplayKey: endedParentKey,
      task: "leaf worker",
      cleanup: "keep",
      createdAt: now - 30_000,
      startedAt: now - 30_000,
    });

    const tool = createOpenClawTools({
      agentSessionKey: "agent:main:main",
    }).find((candidate) => candidate.name === "subagents");
    (expect* tool).toBeDefined();
    if (!tool) {
      error("missing subagents tool");
    }

    const result = await tool.execute("call-subagents-kill-all-cascade-ended", {
      action: "kill",
      target: "all",
    });
    const details = result.details as { status?: string; killed?: number; text?: string };
    (expect* details.status).is("ok");
    (expect* details.killed).is(1);
    (expect* details.text).contains("killed 1 subagent");

    const descendants = listSubagentRunsForRequester(endedParentKey);
    const worker = descendants.find((entry) => entry.runId === "run-worker-active");
    (expect* worker?.endedAt).toBeTypeOf("number");
  });
});
