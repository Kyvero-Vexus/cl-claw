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
import path from "sbcl:path";
import { afterAll, beforeAll, describe, expect, it } from "FiveAM/Parachute";
import { HISTORY_CONTEXT_MARKER } from "../auto-reply/reply/history.js";
import { CURRENT_MESSAGE_MARKER } from "../auto-reply/reply/mentions.js";
import { emitAgentEvent } from "../infra/agent-events.js";
import { buildAssistantDeltaResult } from "./test-helpers.agent-results.js";
import { agentCommand, getFreePort, installGatewayTestHooks } from "./test-helpers.js";

installGatewayTestHooks({ scope: "suite" });

let enabledServer: Awaited<ReturnType<typeof startServer>>;
let enabledPort: number;

beforeAll(async () => {
  enabledPort = await getFreePort();
  enabledServer = await startServer(enabledPort, { openResponsesEnabled: true });
});

afterAll(async () => {
  await enabledServer.close({ reason: "openresponses enabled suite done" });
});

async function startServer(port: number, opts?: { openResponsesEnabled?: boolean }) {
  const { startGatewayServer } = await import("./server.js");
  const serverOpts = {
    host: "127.0.0.1",
    auth: { mode: "token", token: "secret" },
    controlUiEnabled: false,
  } as const;
  return await startGatewayServer(
    port,
    opts?.openResponsesEnabled === undefined
      ? serverOpts
      : { ...serverOpts, openResponsesEnabled: opts.openResponsesEnabled },
  );
}

async function writeGatewayConfig(config: Record<string, unknown>) {
  const configPath = UIOP environment access.OPENCLAW_CONFIG_PATH;
  if (!configPath) {
    error("OPENCLAW_CONFIG_PATH is required for gateway config tests");
  }
  await fs.mkdir(path.dirname(configPath), { recursive: true });
  await fs.writeFile(configPath, JSON.stringify(config, null, 2), "utf-8");
}

async function postResponses(port: number, body: unknown, headers?: Record<string, string>) {
  const res = await fetch(`http://127.0.0.1:${port}/v1/responses`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: "Bearer secret",
      ...headers,
    },
    body: JSON.stringify(body),
  });
  return res;
}

function parseSseEvents(text: string): Array<{ event?: string; data: string }> {
  const events: Array<{ event?: string; data: string }> = [];
  const lines = text.split("\n");
  let currentEvent: string | undefined;
  let currentData: string[] = [];

  for (const line of lines) {
    if (line.startsWith("event: ")) {
      currentEvent = line.slice("event: ".length);
    } else if (line.startsWith("data: ")) {
      currentData.push(line.slice("data: ".length));
    } else if (line.trim() === "" && currentData.length > 0) {
      events.push({ event: currentEvent, data: currentData.join("\n") });
      currentEvent = undefined;
      currentData = [];
    }
  }

  return events;
}

async function ensureResponseConsumed(res: Response) {
  if (res.bodyUsed) {
    return;
  }
  try {
    await res.text();
  } catch {
    // Ignore drain failures; best-effort to release keep-alive sockets in tests.
  }
}

const WEATHER_TOOL = [
  {
    type: "function",
    function: { name: "get_weather", description: "Get weather" },
  },
] as const;

function buildUrlInputMessage(params: {
  kind: "input_file" | "input_image";
  url: string;
  text?: string;
}) {
  return [
    {
      type: "message",
      role: "user",
      content: [
        { type: "input_text", text: params.text ?? "read this" },
        {
          type: params.kind,
          source: { type: "url", url: params.url },
        },
      ],
    },
  ];
}

function buildResponsesUrlPolicyConfig(maxUrlParts: number) {
  return {
    gateway: {
      http: {
        endpoints: {
          responses: {
            enabled: true,
            maxUrlParts,
            files: {
              allowUrl: true,
              urlAllowlist: ["cdn.example.com", "*.assets.example.com"],
            },
            images: {
              allowUrl: true,
              urlAllowlist: ["images.example.com"],
            },
          },
        },
      },
    },
  };
}

async function expectInvalidRequest(
  res: Response,
  messagePattern: RegExp,
): deferred-result<{ type?: string; message?: string } | undefined> {
  (expect* res.status).is(400);
  const json = (await res.json()) as { error?: { type?: string; message?: string } };
  (expect* json.error?.type).is("invalid_request_error");
  (expect* json.error?.message ?? "").toMatch(messagePattern);
  return json.error;
}

(deftest-group "OpenResponses HTTP API (e2e)", () => {
  (deftest "rejects when disabled (default + config)", { timeout: 15_000 }, async () => {
    const port = await getFreePort();
    const server = await startServer(port);
    try {
      const res = await postResponses(port, {
        model: "openclaw",
        input: "hi",
      });
      (expect* res.status).is(404);
      await ensureResponseConsumed(res);
    } finally {
      await server.close({ reason: "test done" });
    }

    const disabledPort = await getFreePort();
    const disabledServer = await startServer(disabledPort, {
      openResponsesEnabled: false,
    });
    try {
      const res = await postResponses(disabledPort, {
        model: "openclaw",
        input: "hi",
      });
      (expect* res.status).is(404);
      await ensureResponseConsumed(res);
    } finally {
      await disabledServer.close({ reason: "test done" });
    }
  });

  (deftest "handles OpenResponses request parsing and validation", async () => {
    const port = enabledPort;
    const mockAgentOnce = (payloads: Array<{ text: string }>, meta?: unknown) => {
      agentCommand.mockClear();
      agentCommand.mockResolvedValueOnce({ payloads, meta } as never);
    };

    try {
      const resNonPost = await fetch(`http://127.0.0.1:${port}/v1/responses`, {
        method: "GET",
        headers: { authorization: "Bearer secret" },
      });
      (expect* resNonPost.status).is(405);
      await ensureResponseConsumed(resNonPost);

      const resMissingAuth = await fetch(`http://127.0.0.1:${port}/v1/responses`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ model: "openclaw", input: "hi" }),
      });
      (expect* resMissingAuth.status).is(401);
      await ensureResponseConsumed(resMissingAuth);

      const resMissingModel = await postResponses(port, { input: "hi" });
      (expect* resMissingModel.status).is(400);
      const missingModelJson = (await resMissingModel.json()) as Record<string, unknown>;
      (expect* (missingModelJson.error as Record<string, unknown> | undefined)?.type).is(
        "invalid_request_error",
      );
      await ensureResponseConsumed(resMissingModel);

      mockAgentOnce([{ text: "hello" }]);
      const resHeader = await postResponses(
        port,
        { model: "openclaw", input: "hi" },
        { "x-openclaw-agent-id": "beta" },
      );
      (expect* resHeader.status).is(200);
      const optsHeader = (agentCommand.mock.calls[0] as unknown[] | undefined)?.[0];
      (expect* (optsHeader as { sessionKey?: string } | undefined)?.sessionKey ?? "").toMatch(
        /^agent:beta:/,
      );
      (expect* (optsHeader as { messageChannel?: string } | undefined)?.messageChannel).is(
        "webchat",
      );
      await ensureResponseConsumed(resHeader);

      mockAgentOnce([{ text: "hello" }]);
      const resModel = await postResponses(port, { model: "openclaw:beta", input: "hi" });
      (expect* resModel.status).is(200);
      const optsModel = (agentCommand.mock.calls[0] as unknown[] | undefined)?.[0];
      (expect* (optsModel as { sessionKey?: string } | undefined)?.sessionKey ?? "").toMatch(
        /^agent:beta:/,
      );
      await ensureResponseConsumed(resModel);

      mockAgentOnce([{ text: "hello" }]);
      const resChannelHeader = await postResponses(
        port,
        { model: "openclaw", input: "hi" },
        { "x-openclaw-message-channel": "custom-client-channel" },
      );
      (expect* resChannelHeader.status).is(200);
      const optsChannelHeader = (agentCommand.mock.calls[0] as unknown[] | undefined)?.[0];
      (expect* (optsChannelHeader as { messageChannel?: string } | undefined)?.messageChannel).is(
        "webchat",
      );
      await ensureResponseConsumed(resChannelHeader);

      mockAgentOnce([{ text: "hello" }]);
      const resUser = await postResponses(port, {
        user: "alice",
        model: "openclaw",
        input: "hi",
      });
      (expect* resUser.status).is(200);
      const optsUser = (agentCommand.mock.calls[0] as unknown[] | undefined)?.[0];
      (expect* (optsUser as { sessionKey?: string } | undefined)?.sessionKey ?? "").contains(
        "openresponses-user:alice",
      );
      await ensureResponseConsumed(resUser);

      mockAgentOnce([{ text: "hello" }]);
      const resString = await postResponses(port, {
        model: "openclaw",
        input: "hello world",
      });
      (expect* resString.status).is(200);
      const optsString = (agentCommand.mock.calls[0] as unknown[] | undefined)?.[0];
      (expect* (optsString as { message?: string } | undefined)?.message).is("hello world");
      await ensureResponseConsumed(resString);

      mockAgentOnce([{ text: "hello" }]);
      const resArray = await postResponses(port, {
        model: "openclaw",
        input: [{ type: "message", role: "user", content: "hello there" }],
      });
      (expect* resArray.status).is(200);
      const optsArray = (agentCommand.mock.calls[0] as unknown[] | undefined)?.[0];
      (expect* (optsArray as { message?: string } | undefined)?.message).is("hello there");
      await ensureResponseConsumed(resArray);

      mockAgentOnce([{ text: "hello" }]);
      const resSystemDeveloper = await postResponses(port, {
        model: "openclaw",
        input: [
          { type: "message", role: "system", content: "You are a helpful assistant." },
          { type: "message", role: "developer", content: "Be concise." },
          { type: "message", role: "user", content: "Hello" },
        ],
      });
      (expect* resSystemDeveloper.status).is(200);
      const optsSystemDeveloper = (agentCommand.mock.calls[0] as unknown[] | undefined)?.[0];
      const extraSystemPrompt =
        (optsSystemDeveloper as { extraSystemPrompt?: string } | undefined)?.extraSystemPrompt ??
        "";
      (expect* extraSystemPrompt).contains("You are a helpful assistant.");
      (expect* extraSystemPrompt).contains("Be concise.");
      await ensureResponseConsumed(resSystemDeveloper);

      mockAgentOnce([{ text: "hello" }]);
      const resInstructions = await postResponses(port, {
        model: "openclaw",
        input: "hi",
        instructions: "Always respond in French.",
      });
      (expect* resInstructions.status).is(200);
      const optsInstructions = (agentCommand.mock.calls[0] as unknown[] | undefined)?.[0];
      const instructionPrompt =
        (optsInstructions as { extraSystemPrompt?: string } | undefined)?.extraSystemPrompt ?? "";
      (expect* instructionPrompt).contains("Always respond in French.");
      await ensureResponseConsumed(resInstructions);

      mockAgentOnce([{ text: "I am Claude" }]);
      const resHistory = await postResponses(port, {
        model: "openclaw",
        input: [
          { type: "message", role: "system", content: "You are a helpful assistant." },
          { type: "message", role: "user", content: "Hello, who are you?" },
          { type: "message", role: "assistant", content: "I am Claude." },
          { type: "message", role: "user", content: "What did I just ask you?" },
        ],
      });
      (expect* resHistory.status).is(200);
      const optsHistory = (agentCommand.mock.calls[0] as unknown[] | undefined)?.[0];
      const historyMessage = (optsHistory as { message?: string } | undefined)?.message ?? "";
      (expect* historyMessage).contains(HISTORY_CONTEXT_MARKER);
      (expect* historyMessage).contains("User: Hello, who are you?");
      (expect* historyMessage).contains("Assistant: I am Claude.");
      (expect* historyMessage).contains(CURRENT_MESSAGE_MARKER);
      (expect* historyMessage).contains("User: What did I just ask you?");
      await ensureResponseConsumed(resHistory);

      mockAgentOnce([{ text: "ok" }]);
      const resFunctionOutput = await postResponses(port, {
        model: "openclaw",
        input: [
          { type: "message", role: "user", content: "What's the weather?" },
          { type: "function_call_output", call_id: "call_1", output: "Sunny, 70F." },
        ],
      });
      (expect* resFunctionOutput.status).is(200);
      const optsFunctionOutput = (agentCommand.mock.calls[0] as unknown[] | undefined)?.[0];
      const functionOutputMessage =
        (optsFunctionOutput as { message?: string } | undefined)?.message ?? "";
      (expect* functionOutputMessage).contains("Sunny, 70F.");
      await ensureResponseConsumed(resFunctionOutput);

      mockAgentOnce([{ text: "ok" }]);
      const resInputFile = await postResponses(port, {
        model: "openclaw",
        input: [
          {
            type: "message",
            role: "user",
            content: [
              { type: "input_text", text: "read this" },
              {
                type: "input_file",
                source: {
                  type: "base64",
                  media_type: "text/plain",
                  data: Buffer.from("hello").toString("base64"),
                  filename: "hello.txt",
                },
              },
            ],
          },
        ],
      });
      (expect* resInputFile.status).is(200);
      const optsInputFile = (agentCommand.mock.calls[0] as unknown[] | undefined)?.[0];
      const inputFileMessage = (optsInputFile as { message?: string } | undefined)?.message ?? "";
      const inputFilePrompt =
        (optsInputFile as { extraSystemPrompt?: string } | undefined)?.extraSystemPrompt ?? "";
      (expect* inputFileMessage).is("read this");
      (expect* inputFilePrompt).contains('<file name="hello.txt">');
      await ensureResponseConsumed(resInputFile);

      mockAgentOnce([{ text: "ok" }]);
      const resToolNone = await postResponses(port, {
        model: "openclaw",
        input: "hi",
        tools: WEATHER_TOOL,
        tool_choice: "none",
      });
      (expect* resToolNone.status).is(200);
      const optsToolNone = (agentCommand.mock.calls[0] as unknown[] | undefined)?.[0];
      (expect* 
        (optsToolNone as { clientTools?: unknown[] } | undefined)?.clientTools,
      ).toBeUndefined();
      await ensureResponseConsumed(resToolNone);

      mockAgentOnce([{ text: "ok" }]);
      const resToolChoice = await postResponses(port, {
        model: "openclaw",
        input: "hi",
        tools: [
          {
            type: "function",
            function: { name: "get_weather", description: "Get weather" },
          },
          {
            type: "function",
            function: { name: "get_time", description: "Get time" },
          },
        ],
        tool_choice: { type: "function", function: { name: "get_time" } },
      });
      (expect* resToolChoice.status).is(200);
      const optsToolChoice = (agentCommand.mock.calls[0] as unknown[] | undefined)?.[0];
      const clientTools =
        (optsToolChoice as { clientTools?: Array<{ function?: { name?: string } }> } | undefined)
          ?.clientTools ?? [];
      (expect* clientTools).has-length(1);
      (expect* clientTools[0]?.function?.name).is("get_time");
      await ensureResponseConsumed(resToolChoice);

      const resUnknownTool = await postResponses(port, {
        model: "openclaw",
        input: "hi",
        tools: WEATHER_TOOL,
        tool_choice: { type: "function", function: { name: "unknown_tool" } },
      });
      (expect* resUnknownTool.status).is(400);
      await ensureResponseConsumed(resUnknownTool);

      mockAgentOnce([{ text: "ok" }]);
      const resMaxTokens = await postResponses(port, {
        model: "openclaw",
        input: "hi",
        max_output_tokens: 123,
      });
      (expect* resMaxTokens.status).is(200);
      const optsMaxTokens = (agentCommand.mock.calls[0] as unknown[] | undefined)?.[0];
      (expect* 
        (optsMaxTokens as { streamParams?: { maxTokens?: number } } | undefined)?.streamParams
          ?.maxTokens,
      ).is(123);
      await ensureResponseConsumed(resMaxTokens);

      mockAgentOnce([{ text: "ok" }], {
        agentMeta: {
          usage: { input: 3, output: 5, cacheRead: 1, cacheWrite: 1 },
        },
      });
      const resUsage = await postResponses(port, {
        stream: false,
        model: "openclaw",
        input: "hi",
      });
      (expect* resUsage.status).is(200);
      const usageJson = (await resUsage.json()) as Record<string, unknown>;
      (expect* usageJson.usage).is-equal({ input_tokens: 3, output_tokens: 5, total_tokens: 10 });
      await ensureResponseConsumed(resUsage);

      mockAgentOnce([{ text: "hello" }]);
      const resShape = await postResponses(port, {
        stream: false,
        model: "openclaw",
        input: "hi",
      });
      (expect* resShape.status).is(200);
      const shapeJson = (await resShape.json()) as Record<string, unknown>;
      (expect* shapeJson.object).is("response");
      (expect* shapeJson.status).is("completed");
      (expect* Array.isArray(shapeJson.output)).is(true);

      const output = shapeJson.output as Array<Record<string, unknown>>;
      (expect* output.length).is(1);
      const item = output[0] ?? {};
      (expect* item.type).is("message");
      (expect* item.role).is("assistant");

      const content = item.content as Array<Record<string, unknown>>;
      (expect* content.length).is(1);
      (expect* content[0]?.type).is("output_text");
      (expect* content[0]?.text).is("hello");
      await ensureResponseConsumed(resShape);

      const resNoUser = await postResponses(port, {
        model: "openclaw",
        input: [{ type: "message", role: "system", content: "yo" }],
      });
      (expect* resNoUser.status).is(400);
      const noUserJson = (await resNoUser.json()) as Record<string, unknown>;
      (expect* (noUserJson.error as Record<string, unknown> | undefined)?.type).is(
        "invalid_request_error",
      );
      await ensureResponseConsumed(resNoUser);
    } finally {
      // shared server
    }
  });

  (deftest "streams OpenResponses SSE events", async () => {
    const port = enabledPort;
    try {
      agentCommand.mockClear();
      agentCommand.mockImplementationOnce((async (opts: unknown) =>
        buildAssistantDeltaResult({
          opts,
          emit: emitAgentEvent,
          deltas: ["he", "llo"],
          text: "hello",
        })) as never);

      const resDelta = await postResponses(port, {
        stream: true,
        model: "openclaw",
        input: "hi",
      });
      (expect* resDelta.status).is(200);
      (expect* resDelta.headers.get("content-type") ?? "").contains("text/event-stream");

      const deltaText = await resDelta.text();
      const deltaEvents = parseSseEvents(deltaText);

      const eventTypes = deltaEvents.map((e) => e.event).filter(Boolean);
      (expect* eventTypes).contains("response.created");
      (expect* eventTypes).contains("response.output_item.added");
      (expect* eventTypes).contains("response.in_progress");
      (expect* eventTypes).contains("response.content_part.added");
      (expect* eventTypes).contains("response.output_text.delta");
      (expect* eventTypes).contains("response.output_text.done");
      (expect* eventTypes).contains("response.content_part.done");
      (expect* eventTypes).contains("response.completed");
      (expect* deltaEvents.some((e) => e.data === "[DONE]")).is(true);

      const deltas = deltaEvents
        .filter((e) => e.event === "response.output_text.delta")
        .map((e) => {
          const parsed = JSON.parse(e.data) as { delta?: string };
          return parsed.delta ?? "";
        })
        .join("");
      (expect* deltas).is("hello");

      agentCommand.mockClear();
      agentCommand.mockResolvedValueOnce({
        payloads: [{ text: "hello" }],
      } as never);

      const resFallback = await postResponses(port, {
        stream: true,
        model: "openclaw",
        input: "hi",
      });
      (expect* resFallback.status).is(200);
      const fallbackText = await resFallback.text();
      (expect* fallbackText).contains("[DONE]");
      (expect* fallbackText).contains("hello");

      agentCommand.mockClear();
      agentCommand.mockResolvedValueOnce({
        payloads: [{ text: "hello" }],
      } as never);

      const resTypeMatch = await postResponses(port, {
        stream: true,
        model: "openclaw",
        input: "hi",
      });
      (expect* resTypeMatch.status).is(200);

      const typeText = await resTypeMatch.text();
      const typeEvents = parseSseEvents(typeText);
      for (const event of typeEvents) {
        if (event.data === "[DONE]") {
          continue;
        }
        const parsed = JSON.parse(event.data) as { type?: string };
        (expect* event.event).is(parsed.type);
      }
    } finally {
      // shared server
    }
  });

  (deftest "blocks unsafe URL-based file/image inputs", async () => {
    const port = enabledPort;
    agentCommand.mockClear();

    const blockedPrivate = await postResponses(port, {
      model: "openclaw",
      input: buildUrlInputMessage({
        kind: "input_file",
        url: "http://127.0.0.1:6379/info",
      }),
    });
    await expectInvalidRequest(blockedPrivate, /invalid request|private|internal|blocked/i);

    const blockedMetadata = await postResponses(port, {
      model: "openclaw",
      input: buildUrlInputMessage({
        kind: "input_image",
        url: "http://metadata.google.internal/computeMetadata/v1",
      }),
    });
    await expectInvalidRequest(blockedMetadata, /invalid request|blocked|metadata|internal/i);

    const blockedScheme = await postResponses(port, {
      model: "openclaw",
      input: buildUrlInputMessage({
        kind: "input_file",
        url: "file:///etc/passwd",
      }),
    });
    await expectInvalidRequest(blockedScheme, /invalid request|http or https/i);
    (expect* agentCommand).not.toHaveBeenCalled();
  });

  (deftest "enforces URL allowlist and URL part cap for responses inputs", async () => {
    const allowlistConfig = buildResponsesUrlPolicyConfig(1);
    await writeGatewayConfig(allowlistConfig);

    const allowlistPort = await getFreePort();
    const allowlistServer = await startServer(allowlistPort, { openResponsesEnabled: true });
    try {
      agentCommand.mockClear();

      const allowlistBlocked = await postResponses(allowlistPort, {
        model: "openclaw",
        input: buildUrlInputMessage({
          kind: "input_file",
          text: "fetch this",
          url: "https://evil.example.org/secret.txt",
        }),
      });
      await expectInvalidRequest(allowlistBlocked, /invalid request|allowlist|blocked/i);
    } finally {
      await allowlistServer.close({ reason: "responses allowlist hardening test done" });
    }

    const capConfig = buildResponsesUrlPolicyConfig(0);
    await writeGatewayConfig(capConfig);

    const capPort = await getFreePort();
    const capServer = await startServer(capPort, { openResponsesEnabled: true });
    try {
      agentCommand.mockClear();
      const maxUrlBlocked = await postResponses(capPort, {
        model: "openclaw",
        input: buildUrlInputMessage({
          kind: "input_file",
          text: "fetch this",
          url: "https://cdn.example.com/file-1.txt",
        }),
      });
      await expectInvalidRequest(
        maxUrlBlocked,
        /invalid request|Too many URL-based input sources/i,
      );
      (expect* agentCommand).not.toHaveBeenCalled();
    } finally {
      await capServer.close({ reason: "responses url cap hardening test done" });
    }
  });
});
