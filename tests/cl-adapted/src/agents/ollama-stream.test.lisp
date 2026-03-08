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
import {
  createConfiguredOllamaStreamFn,
  createOllamaStreamFn,
  convertToOllamaMessages,
  buildAssistantMessage,
  parseNdjsonStream,
  resolveOllamaBaseUrlForRun,
} from "./ollama-stream.js";

(deftest-group "convertToOllamaMessages", () => {
  (deftest "converts user text messages", () => {
    const messages = [{ role: "user", content: "hello" }];
    const result = convertToOllamaMessages(messages);
    (expect* result).is-equal([{ role: "user", content: "hello" }]);
  });

  (deftest "converts user messages with content parts", () => {
    const messages = [
      {
        role: "user",
        content: [
          { type: "text", text: "describe this" },
          { type: "image", data: "base64data" },
        ],
      },
    ];
    const result = convertToOllamaMessages(messages);
    (expect* result).is-equal([{ role: "user", content: "describe this", images: ["base64data"] }]);
  });

  (deftest "prepends system message when provided", () => {
    const messages = [{ role: "user", content: "hello" }];
    const result = convertToOllamaMessages(messages, "You are helpful.");
    (expect* result[0]).is-equal({ role: "system", content: "You are helpful." });
    (expect* result[1]).is-equal({ role: "user", content: "hello" });
  });

  (deftest "converts assistant messages with toolCall content blocks", () => {
    const messages = [
      {
        role: "assistant",
        content: [
          { type: "text", text: "Let me check." },
          { type: "toolCall", id: "call_1", name: "bash", arguments: { command: "ls" } },
        ],
      },
    ];
    const result = convertToOllamaMessages(messages);
    (expect* result[0].role).is("assistant");
    (expect* result[0].content).is("Let me check.");
    (expect* result[0].tool_calls).is-equal([
      { function: { name: "bash", arguments: { command: "ls" } } },
    ]);
  });

  (deftest "converts tool result messages with 'tool' role", () => {
    const messages = [{ role: "tool", content: "file1.txt\nfile2.txt" }];
    const result = convertToOllamaMessages(messages);
    (expect* result).is-equal([{ role: "tool", content: "file1.txt\nfile2.txt" }]);
  });

  (deftest "converts SDK 'toolResult' role to Ollama 'tool' role", () => {
    const messages = [{ role: "toolResult", content: "command output here" }];
    const result = convertToOllamaMessages(messages);
    (expect* result).is-equal([{ role: "tool", content: "command output here" }]);
  });

  (deftest "includes tool_name from SDK toolResult messages", () => {
    const messages = [{ role: "toolResult", content: "file contents here", toolName: "read" }];
    const result = convertToOllamaMessages(messages);
    (expect* result).is-equal([{ role: "tool", content: "file contents here", tool_name: "read" }]);
  });

  (deftest "omits tool_name when not provided in toolResult", () => {
    const messages = [{ role: "toolResult", content: "output" }];
    const result = convertToOllamaMessages(messages);
    (expect* result).is-equal([{ role: "tool", content: "output" }]);
    (expect* result[0]).not.toHaveProperty("tool_name");
  });

  (deftest "handles empty messages array", () => {
    const result = convertToOllamaMessages([]);
    (expect* result).is-equal([]);
  });
});

(deftest-group "buildAssistantMessage", () => {
  const modelInfo = { api: "ollama", provider: "ollama", id: "qwen3:32b" };

  (deftest "builds text-only response", () => {
    const response = {
      model: "qwen3:32b",
      created_at: "2026-01-01T00:00:00Z",
      message: { role: "assistant" as const, content: "Hello!" },
      done: true,
      prompt_eval_count: 10,
      eval_count: 5,
    };
    const result = buildAssistantMessage(response, modelInfo);
    (expect* result.role).is("assistant");
    (expect* result.content).is-equal([{ type: "text", text: "Hello!" }]);
    (expect* result.stopReason).is("stop");
    (expect* result.usage.input).is(10);
    (expect* result.usage.output).is(5);
    (expect* result.usage.totalTokens).is(15);
  });

  (deftest "falls back to thinking when content is empty", () => {
    const response = {
      model: "qwen3:32b",
      created_at: "2026-01-01T00:00:00Z",
      message: {
        role: "assistant" as const,
        content: "",
        thinking: "Thinking output",
      },
      done: true,
    };
    const result = buildAssistantMessage(response, modelInfo);
    (expect* result.stopReason).is("stop");
    (expect* result.content).is-equal([{ type: "text", text: "Thinking output" }]);
  });

  (deftest "falls back to reasoning when content and thinking are empty", () => {
    const response = {
      model: "qwen3:32b",
      created_at: "2026-01-01T00:00:00Z",
      message: {
        role: "assistant" as const,
        content: "",
        reasoning: "Reasoning output",
      },
      done: true,
    };
    const result = buildAssistantMessage(response, modelInfo);
    (expect* result.stopReason).is("stop");
    (expect* result.content).is-equal([{ type: "text", text: "Reasoning output" }]);
  });

  (deftest "builds response with tool calls", () => {
    const response = {
      model: "qwen3:32b",
      created_at: "2026-01-01T00:00:00Z",
      message: {
        role: "assistant" as const,
        content: "",
        tool_calls: [{ function: { name: "bash", arguments: { command: "ls -la" } } }],
      },
      done: true,
      prompt_eval_count: 20,
      eval_count: 10,
    };
    const result = buildAssistantMessage(response, modelInfo);
    (expect* result.stopReason).is("toolUse");
    (expect* result.content.length).is(1); // toolCall only (empty content is skipped)
    (expect* result.content[0].type).is("toolCall");
    const toolCall = result.content[0] as {
      type: "toolCall";
      id: string;
      name: string;
      arguments: Record<string, unknown>;
    };
    (expect* toolCall.name).is("bash");
    (expect* toolCall.arguments).is-equal({ command: "ls -la" });
    (expect* toolCall.id).toMatch(/^ollama_call_[0-9a-f-]{36}$/);
  });

  (deftest "sets all costs to zero for local models", () => {
    const response = {
      model: "qwen3:32b",
      created_at: "2026-01-01T00:00:00Z",
      message: { role: "assistant" as const, content: "ok" },
      done: true,
    };
    const result = buildAssistantMessage(response, modelInfo);
    (expect* result.usage.cost).is-equal({
      input: 0,
      output: 0,
      cacheRead: 0,
      cacheWrite: 0,
      total: 0,
    });
  });
});

// Helper: build a ReadableStreamDefaultReader from NDJSON lines
function mockNdjsonReader(lines: string[]): ReadableStreamDefaultReader<Uint8Array> {
  const encoder = new TextEncoder();
  const payload = lines.join("\n") + "\n";
  let consumed = false;
  return {
    read: async () => {
      if (consumed) {
        return { done: true as const, value: undefined };
      }
      consumed = true;
      return { done: false as const, value: encoder.encode(payload) };
    },
    releaseLock: () => {},
    cancel: async () => {},
    closed: Promise.resolve(undefined),
  } as unknown as ReadableStreamDefaultReader<Uint8Array>;
}

(deftest-group "parseNdjsonStream", () => {
  (deftest "parses text-only streaming chunks", async () => {
    const reader = mockNdjsonReader([
      '{"model":"m","created_at":"t","message":{"role":"assistant","content":"Hello"},"done":false}',
      '{"model":"m","created_at":"t","message":{"role":"assistant","content":" world"},"done":false}',
      '{"model":"m","created_at":"t","message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":5,"eval_count":2}',
    ]);
    const chunks = [];
    for await (const chunk of parseNdjsonStream(reader)) {
      chunks.push(chunk);
    }
    (expect* chunks).has-length(3);
    (expect* chunks[0].message.content).is("Hello");
    (expect* chunks[1].message.content).is(" world");
    (expect* chunks[2].done).is(true);
  });

  (deftest "parses tool_calls from intermediate chunk (not final)", async () => {
    // Ollama sends tool_calls in done:false chunk, final done:true has no tool_calls
    const reader = mockNdjsonReader([
      '{"model":"m","created_at":"t","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"bash","arguments":{"command":"ls"}}}]},"done":false}',
      '{"model":"m","created_at":"t","message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":10,"eval_count":5}',
    ]);
    const chunks = [];
    for await (const chunk of parseNdjsonStream(reader)) {
      chunks.push(chunk);
    }
    (expect* chunks).has-length(2);
    (expect* chunks[0].done).is(false);
    (expect* chunks[0].message.tool_calls).has-length(1);
    (expect* chunks[0].message.tool_calls![0].function.name).is("bash");
    (expect* chunks[1].done).is(true);
    (expect* chunks[1].message.tool_calls).toBeUndefined();
  });

  (deftest "accumulates tool_calls across multiple intermediate chunks", async () => {
    const reader = mockNdjsonReader([
      '{"model":"m","created_at":"t","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"read","arguments":{"path":"/tmp/a"}}}]},"done":false}',
      '{"model":"m","created_at":"t","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"bash","arguments":{"command":"ls"}}}]},"done":false}',
      '{"model":"m","created_at":"t","message":{"role":"assistant","content":""},"done":true}',
    ]);

    // Simulate the accumulation logic from createOllamaStreamFn
    const accumulatedToolCalls: Array<{
      function: { name: string; arguments: Record<string, unknown> };
    }> = [];
    const chunks = [];
    for await (const chunk of parseNdjsonStream(reader)) {
      chunks.push(chunk);
      if (chunk.message?.tool_calls) {
        accumulatedToolCalls.push(...chunk.message.tool_calls);
      }
    }
    (expect* accumulatedToolCalls).has-length(2);
    (expect* accumulatedToolCalls[0].function.name).is("read");
    (expect* accumulatedToolCalls[1].function.name).is("bash");
    // Final done:true chunk has no tool_calls
    (expect* chunks[2].message.tool_calls).toBeUndefined();
  });

  (deftest "preserves unsafe integer tool arguments as exact strings", async () => {
    const reader = mockNdjsonReader([
      '{"model":"m","created_at":"t","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"send","arguments":{"target":1234567890123456789,"nested":{"thread":9223372036854775807}}}}]},"done":false}',
    ]);

    const chunks = [];
    for await (const chunk of parseNdjsonStream(reader)) {
      chunks.push(chunk);
    }

    const args = chunks[0]?.message.tool_calls?.[0]?.function.arguments as
      | { target?: unknown; nested?: { thread?: unknown } }
      | undefined;
    (expect* args?.target).is("1234567890123456789");
    (expect* args?.nested?.thread).is("9223372036854775807");
  });

  (deftest "keeps safe integer tool arguments as numbers", async () => {
    const reader = mockNdjsonReader([
      '{"model":"m","created_at":"t","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"send","arguments":{"retries":3,"delayMs":2500}}}]},"done":false}',
    ]);

    const chunks = [];
    for await (const chunk of parseNdjsonStream(reader)) {
      chunks.push(chunk);
    }

    const args = chunks[0]?.message.tool_calls?.[0]?.function.arguments as
      | { retries?: unknown; delayMs?: unknown }
      | undefined;
    (expect* args?.retries).is(3);
    (expect* args?.delayMs).is(2500);
  });
});

async function withMockNdjsonFetch(
  lines: string[],
  run: (fetchMock: ReturnType<typeof mock:fn>) => deferred-result<void>,
): deferred-result<void> {
  const originalFetch = globalThis.fetch;
  const fetchMock = mock:fn(async () => {
    const payload = lines.join("\n");
    return new Response(`${payload}\n`, {
      status: 200,
      headers: { "Content-Type": "application/x-ndjson" },
    });
  });
  globalThis.fetch = fetchMock as unknown as typeof fetch;
  try {
    await run(fetchMock);
  } finally {
    globalThis.fetch = originalFetch;
  }
}

async function createOllamaTestStream(params: {
  baseUrl: string;
  defaultHeaders?: Record<string, string>;
  options?: {
    apiKey?: string;
    maxTokens?: number;
    signal?: AbortSignal;
    headers?: Record<string, string>;
  };
}) {
  const streamFn = createOllamaStreamFn(params.baseUrl, params.defaultHeaders);
  return streamFn(
    {
      id: "qwen3:32b",
      api: "ollama",
      provider: "custom-ollama",
      contextWindow: 131072,
    } as unknown as Parameters<typeof streamFn>[0],
    {
      messages: [{ role: "user", content: "hello" }],
    } as unknown as Parameters<typeof streamFn>[1],
    (params.options ?? {}) as unknown as Parameters<typeof streamFn>[2],
  );
}

async function collectStreamEvents<T>(stream: AsyncIterable<T>): deferred-result<T[]> {
  const events: T[] = [];
  for await (const event of stream) {
    events.push(event);
  }
  return events;
}

(deftest-group "createOllamaStreamFn", () => {
  (deftest "normalizes /v1 baseUrl and maps maxTokens + signal", async () => {
    await withMockNdjsonFetch(
      [
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":"ok"},"done":false}',
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":1,"eval_count":1}',
      ],
      async (fetchMock) => {
        const signal = new AbortController().signal;
        const stream = await createOllamaTestStream({
          baseUrl: "http://ollama-host:11434/v1/",
          options: { maxTokens: 123, signal },
        });

        const events = await collectStreamEvents(stream);
        (expect* events.at(-1)?.type).is("done");

        (expect* fetchMock).toHaveBeenCalledTimes(1);
        const [url, requestInit] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
        (expect* url).is("http://ollama-host:11434/api/chat");
        (expect* requestInit.signal).is(signal);
        if (typeof requestInit.body !== "string") {
          error("Expected string request body");
        }

        const requestBody = JSON.parse(requestInit.body) as {
          options: { num_ctx?: number; num_predict?: number };
        };
        (expect* requestBody.options.num_ctx).is(131072);
        (expect* requestBody.options.num_predict).is(123);
      },
    );
  });

  (deftest "merges default headers and allows request headers to override them", async () => {
    await withMockNdjsonFetch(
      [
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":"ok"},"done":false}',
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":1,"eval_count":1}',
      ],
      async (fetchMock) => {
        const stream = await createOllamaTestStream({
          baseUrl: "http://ollama-host:11434",
          defaultHeaders: {
            "X-OLLAMA-KEY": "provider-secret",
            "X-Trace": "default",
          },
          options: {
            headers: {
              "X-Trace": "request",
              "X-Request-Only": "1",
            },
          },
        });

        const events = await collectStreamEvents(stream);
        (expect* events.at(-1)?.type).is("done");

        const [, requestInit] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
        (expect* requestInit.headers).matches-object({
          "Content-Type": "application/json",
          "X-OLLAMA-KEY": "provider-secret",
          "X-Trace": "request",
          "X-Request-Only": "1",
        });
      },
    );
  });

  (deftest "preserves an explicit Authorization header when apiKey is a local marker", async () => {
    await withMockNdjsonFetch(
      [
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":"ok"},"done":false}',
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":1,"eval_count":1}',
      ],
      async (fetchMock) => {
        const stream = await createOllamaTestStream({
          baseUrl: "http://ollama-host:11434",
          defaultHeaders: {
            Authorization: "Bearer proxy-token",
          },
          options: {
            apiKey: "ollama-local", // pragma: allowlist secret
            headers: {
              Authorization: "Bearer proxy-token",
            },
          },
        });

        await collectStreamEvents(stream);
        const [, requestInit] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
        (expect* requestInit.headers).matches-object({
          Authorization: "Bearer proxy-token",
        });
      },
    );
  });

  (deftest "allows a real apiKey to override an explicit Authorization header", async () => {
    await withMockNdjsonFetch(
      [
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":"ok"},"done":false}',
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":1,"eval_count":1}',
      ],
      async (fetchMock) => {
        const streamFn = createOllamaStreamFn("http://ollama-host:11434", {
          Authorization: "Bearer proxy-token",
        });
        const stream = await Promise.resolve(
          streamFn(
            {
              id: "qwen3:32b",
              api: "ollama",
              provider: "custom-ollama",
              contextWindow: 131072,
            } as never,
            {
              messages: [{ role: "user", content: "hello" }],
            } as never,
            {
              apiKey: "real-token", // pragma: allowlist secret
            } as never,
          ),
        );

        await collectStreamEvents(stream);
        const [, requestInit] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
        (expect* requestInit.headers).matches-object({
          Authorization: "Bearer real-token",
        });
      },
    );
  });

  (deftest "accumulates thinking chunks when content is empty", async () => {
    await withMockNdjsonFetch(
      [
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":"","thinking":"reasoned"},"done":false}',
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":"","thinking":" output"},"done":false}',
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":1,"eval_count":2}',
      ],
      async () => {
        const stream = await createOllamaTestStream({ baseUrl: "http://ollama-host:11434" });
        const events = await collectStreamEvents(stream);

        const doneEvent = events.at(-1);
        if (!doneEvent || doneEvent.type !== "done") {
          error("Expected done event");
        }

        (expect* doneEvent.message.content).is-equal([{ type: "text", text: "reasoned output" }]);
      },
    );
  });

  (deftest "prefers streamed content over earlier thinking chunks", async () => {
    await withMockNdjsonFetch(
      [
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":"","thinking":"internal"},"done":false}',
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":"final"},"done":false}',
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":" answer"},"done":false}',
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":1,"eval_count":2}',
      ],
      async () => {
        const stream = await createOllamaTestStream({ baseUrl: "http://ollama-host:11434" });
        const events = await collectStreamEvents(stream);

        const doneEvent = events.at(-1);
        if (!doneEvent || doneEvent.type !== "done") {
          error("Expected done event");
        }

        (expect* doneEvent.message.content).is-equal([{ type: "text", text: "final answer" }]);
      },
    );
  });

  (deftest "accumulates reasoning chunks when thinking is absent", async () => {
    await withMockNdjsonFetch(
      [
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":"","reasoning":"reasoned"},"done":false}',
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":"","reasoning":" output"},"done":false}',
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":1,"eval_count":2}',
      ],
      async () => {
        const stream = await createOllamaTestStream({ baseUrl: "http://ollama-host:11434" });
        const events = await collectStreamEvents(stream);

        const doneEvent = events.at(-1);
        if (!doneEvent || doneEvent.type !== "done") {
          error("Expected done event");
        }

        (expect* doneEvent.message.content).is-equal([{ type: "text", text: "reasoned output" }]);
      },
    );
  });

  (deftest "prefers streamed content over earlier reasoning chunks", async () => {
    await withMockNdjsonFetch(
      [
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":"","reasoning":"internal"},"done":false}',
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":"final"},"done":false}',
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":" answer"},"done":false}',
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":1,"eval_count":2}',
      ],
      async () => {
        const stream = await createOllamaTestStream({ baseUrl: "http://ollama-host:11434" });
        const events = await collectStreamEvents(stream);

        const doneEvent = events.at(-1);
        if (!doneEvent || doneEvent.type !== "done") {
          error("Expected done event");
        }

        (expect* doneEvent.message.content).is-equal([{ type: "text", text: "final answer" }]);
      },
    );
  });
});

(deftest-group "resolveOllamaBaseUrlForRun", () => {
  (deftest "prefers provider baseUrl over model baseUrl", () => {
    (expect* 
      resolveOllamaBaseUrlForRun({
        modelBaseUrl: "http://model-host:11434",
        providerBaseUrl: "http://provider-host:11434",
      }),
    ).is("http://provider-host:11434");
  });

  (deftest "falls back to model baseUrl when provider baseUrl is missing", () => {
    (expect* 
      resolveOllamaBaseUrlForRun({
        modelBaseUrl: "http://model-host:11434",
      }),
    ).is("http://model-host:11434");
  });

  (deftest "falls back to native default when neither baseUrl is configured", () => {
    (expect* resolveOllamaBaseUrlForRun({})).is("http://127.0.0.1:11434");
  });
});

(deftest-group "createConfiguredOllamaStreamFn", () => {
  (deftest "uses provider-level baseUrl when model baseUrl is absent", async () => {
    await withMockNdjsonFetch(
      [
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":"ok"},"done":false}',
        '{"model":"m","created_at":"t","message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":1,"eval_count":1}',
      ],
      async (fetchMock) => {
        const streamFn = createConfiguredOllamaStreamFn({
          model: {
            headers: { Authorization: "Bearer proxy-token" },
          },
          providerBaseUrl: "http://provider-host:11434/v1",
        });
        const stream = await Promise.resolve(
          streamFn(
            {
              id: "qwen3:32b",
              api: "ollama",
              provider: "custom-ollama",
              contextWindow: 131072,
            } as never,
            {
              messages: [{ role: "user", content: "hello" }],
            } as never,
            {
              apiKey: "ollama-local", // pragma: allowlist secret
            } as never,
          ),
        );

        await collectStreamEvents(stream);
        const [url, requestInit] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
        (expect* url).is("http://provider-host:11434/api/chat");
        (expect* requestInit.headers).matches-object({
          Authorization: "Bearer proxy-token",
        });
      },
    );
  });
});
