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
import type { OpenClawConfig } from "../../../config/config.js";
import { resolveOllamaBaseUrlForRun } from "../../ollama-stream.js";
import {
  buildAfterTurnLegacyCompactionParams,
  composeSystemPromptWithHookContext,
  isOllamaCompatProvider,
  prependSystemPromptAddition,
  resolveAttemptFsWorkspaceOnly,
  resolveOllamaCompatNumCtxEnabled,
  resolvePromptBuildHookResult,
  resolvePromptModeForSession,
  shouldInjectOllamaCompatNumCtx,
  decodeHtmlEntitiesInObject,
  wrapOllamaCompatNumCtx,
  wrapStreamFnTrimToolCallNames,
} from "./attempt.js";

function createOllamaProviderConfig(injectNumCtxForOpenAICompat: boolean): OpenClawConfig {
  return {
    models: {
      providers: {
        ollama: {
          baseUrl: "http://127.0.0.1:11434/v1",
          api: "openai-completions",
          injectNumCtxForOpenAICompat,
          models: [],
        },
      },
    },
  };
}

(deftest-group "resolvePromptBuildHookResult", () => {
  function createLegacyOnlyHookRunner() {
    return {
      hasHooks: mock:fn(
        (hookName: "before_prompt_build" | "before_agent_start") =>
          hookName === "before_agent_start",
      ),
      runBeforePromptBuild: mock:fn(async () => undefined),
      runBeforeAgentStart: mock:fn(async () => ({ prependContext: "from-hook" })),
    };
  }

  (deftest "reuses precomputed legacy before_agent_start result without invoking hook again", async () => {
    const hookRunner = createLegacyOnlyHookRunner();
    const result = await resolvePromptBuildHookResult({
      prompt: "hello",
      messages: [],
      hookCtx: {},
      hookRunner,
      legacyBeforeAgentStartResult: { prependContext: "from-cache", systemPrompt: "legacy-system" },
    });

    (expect* hookRunner.runBeforeAgentStart).not.toHaveBeenCalled();
    (expect* result).is-equal({
      prependContext: "from-cache",
      systemPrompt: "legacy-system",
      prependSystemContext: undefined,
      appendSystemContext: undefined,
    });
  });

  (deftest "calls legacy hook when precomputed result is absent", async () => {
    const hookRunner = createLegacyOnlyHookRunner();
    const messages = [{ role: "user", content: "ctx" }];
    const result = await resolvePromptBuildHookResult({
      prompt: "hello",
      messages,
      hookCtx: {},
      hookRunner,
    });

    (expect* hookRunner.runBeforeAgentStart).toHaveBeenCalledTimes(1);
    (expect* hookRunner.runBeforeAgentStart).toHaveBeenCalledWith({ prompt: "hello", messages }, {});
    (expect* result.prependContext).is("from-hook");
  });

  (deftest "merges prompt-build and legacy context fields in deterministic order", async () => {
    const hookRunner = {
      hasHooks: mock:fn(() => true),
      runBeforePromptBuild: mock:fn(async () => ({
        prependContext: "prompt context",
        prependSystemContext: "prompt prepend",
        appendSystemContext: "prompt append",
      })),
      runBeforeAgentStart: mock:fn(async () => ({
        prependContext: "legacy context",
        prependSystemContext: "legacy prepend",
        appendSystemContext: "legacy append",
      })),
    };

    const result = await resolvePromptBuildHookResult({
      prompt: "hello",
      messages: [],
      hookCtx: {},
      hookRunner,
    });

    (expect* result.prependContext).is("prompt context\n\nlegacy context");
    (expect* result.prependSystemContext).is("prompt prepend\n\nlegacy prepend");
    (expect* result.appendSystemContext).is("prompt append\n\nlegacy append");
  });
});

(deftest-group "composeSystemPromptWithHookContext", () => {
  (deftest "returns undefined when no hook system context is provided", () => {
    (expect* composeSystemPromptWithHookContext({ baseSystemPrompt: "base" })).toBeUndefined();
  });

  (deftest "builds prepend/base/append system prompt order", () => {
    (expect* 
      composeSystemPromptWithHookContext({
        baseSystemPrompt: "  base system  ",
        prependSystemContext: "  prepend  ",
        appendSystemContext: "  append  ",
      }),
    ).is("prepend\n\nbase system\n\nappend");
  });

  (deftest "avoids blank separators when base system prompt is empty", () => {
    (expect* 
      composeSystemPromptWithHookContext({
        baseSystemPrompt: "   ",
        appendSystemContext: "  append only  ",
      }),
    ).is("append only");
  });
});

(deftest-group "resolvePromptModeForSession", () => {
  (deftest "uses minimal mode for subagent sessions", () => {
    (expect* resolvePromptModeForSession("agent:main:subagent:child")).is("minimal");
  });

  (deftest "uses full mode for cron sessions", () => {
    (expect* resolvePromptModeForSession("agent:main:cron:job-1")).is("full");
    (expect* resolvePromptModeForSession("agent:main:cron:job-1:run:run-abc")).is("full");
  });
});

(deftest-group "resolveAttemptFsWorkspaceOnly", () => {
  (deftest "uses global tools.fs.workspaceOnly when agent has no override", () => {
    const cfg: OpenClawConfig = {
      tools: {
        fs: { workspaceOnly: true },
      },
    };

    (expect* 
      resolveAttemptFsWorkspaceOnly({
        config: cfg,
        sessionAgentId: "main",
      }),
    ).is(true);
  });

  (deftest "prefers agent-specific tools.fs.workspaceOnly override", () => {
    const cfg: OpenClawConfig = {
      tools: {
        fs: { workspaceOnly: true },
      },
      agents: {
        list: [
          {
            id: "main",
            tools: {
              fs: { workspaceOnly: false },
            },
          },
        ],
      },
    };

    (expect* 
      resolveAttemptFsWorkspaceOnly({
        config: cfg,
        sessionAgentId: "main",
      }),
    ).is(false);
  });
});
(deftest-group "wrapStreamFnTrimToolCallNames", () => {
  function createFakeStream(params: { events: unknown[]; resultMessage: unknown }): {
    result: () => deferred-result<unknown>;
    [Symbol.asyncIterator]: () => AsyncIterator<unknown>;
  } {
    return {
      async result() {
        return params.resultMessage;
      },
      [Symbol.asyncIterator]() {
        return (async function* () {
          for (const event of params.events) {
            yield event;
          }
        })();
      },
    };
  }

  async function invokeWrappedStream(
    baseFn: (...args: never[]) => unknown,
    allowedToolNames?: Set<string>,
  ) {
    const wrappedFn = wrapStreamFnTrimToolCallNames(baseFn as never, allowedToolNames);
    return await wrappedFn({} as never, {} as never, {} as never);
  }

  function createEventStream(params: {
    event: unknown;
    finalToolCall: { type: string; name: string };
  }) {
    const finalMessage = { role: "assistant", content: [params.finalToolCall] };
    const baseFn = mock:fn(() =>
      createFakeStream({ events: [params.event], resultMessage: finalMessage }),
    );
    return { baseFn, finalMessage };
  }

  (deftest "trims whitespace from live streamed tool call names and final result message", async () => {
    const partialToolCall = { type: "toolCall", name: " read " };
    const messageToolCall = { type: "toolCall", name: " exec " };
    const finalToolCall = { type: "toolCall", name: " write " };
    const event = {
      type: "toolcall_delta",
      partial: { role: "assistant", content: [partialToolCall] },
      message: { role: "assistant", content: [messageToolCall] },
    };
    const { baseFn, finalMessage } = createEventStream({ event, finalToolCall });

    const stream = await invokeWrappedStream(baseFn);

    const seenEvents: unknown[] = [];
    for await (const item of stream) {
      seenEvents.push(item);
    }
    const result = await stream.result();

    (expect* seenEvents).has-length(1);
    (expect* partialToolCall.name).is("read");
    (expect* messageToolCall.name).is("exec");
    (expect* finalToolCall.name).is("write");
    (expect* result).is(finalMessage);
    (expect* baseFn).toHaveBeenCalledTimes(1);
  });

  (deftest "supports async stream functions that return a promise", async () => {
    const finalToolCall = { type: "toolCall", name: " browser " };
    const finalMessage = { role: "assistant", content: [finalToolCall] };
    const baseFn = mock:fn(async () =>
      createFakeStream({
        events: [],
        resultMessage: finalMessage,
      }),
    );

    const stream = await invokeWrappedStream(baseFn);
    const result = await stream.result();

    (expect* finalToolCall.name).is("browser");
    (expect* result).is(finalMessage);
    (expect* baseFn).toHaveBeenCalledTimes(1);
  });
  (deftest "normalizes common tool aliases when the canonical name is allowed", async () => {
    const finalToolCall = { type: "toolCall", name: " BASH " };
    const finalMessage = { role: "assistant", content: [finalToolCall] };
    const baseFn = mock:fn(() =>
      createFakeStream({
        events: [],
        resultMessage: finalMessage,
      }),
    );

    const stream = await invokeWrappedStream(baseFn, new Set(["exec"]));
    const result = await stream.result();

    (expect* finalToolCall.name).is("exec");
    (expect* result).is(finalMessage);
  });

  (deftest "maps provider-prefixed tool names to allowed canonical tools", async () => {
    const partialToolCall = { type: "toolCall", name: " functions.read " };
    const messageToolCall = { type: "toolCall", name: " functions.write " };
    const finalToolCall = { type: "toolCall", name: " tools/exec " };
    const event = {
      type: "toolcall_delta",
      partial: { role: "assistant", content: [partialToolCall] },
      message: { role: "assistant", content: [messageToolCall] },
    };
    const { baseFn } = createEventStream({ event, finalToolCall });

    const stream = await invokeWrappedStream(baseFn, new Set(["read", "write", "exec"]));

    for await (const _item of stream) {
      // drain
    }
    await stream.result();

    (expect* partialToolCall.name).is("read");
    (expect* messageToolCall.name).is("write");
    (expect* finalToolCall.name).is("exec");
  });

  (deftest "normalizes toolUse and functionCall names before dispatch", async () => {
    const partialToolCall = { type: "toolUse", name: " functions.read " };
    const messageToolCall = { type: "functionCall", name: " functions.exec " };
    const finalToolCall = { type: "toolUse", name: " tools/write " };
    const event = {
      type: "toolcall_delta",
      partial: { role: "assistant", content: [partialToolCall] },
      message: { role: "assistant", content: [messageToolCall] },
    };
    const finalMessage = { role: "assistant", content: [finalToolCall] };
    const baseFn = mock:fn(() =>
      createFakeStream({
        events: [event],
        resultMessage: finalMessage,
      }),
    );

    const stream = await invokeWrappedStream(baseFn, new Set(["read", "write", "exec"]));

    for await (const _item of stream) {
      // drain
    }
    const result = await stream.result();

    (expect* partialToolCall.name).is("read");
    (expect* messageToolCall.name).is("exec");
    (expect* finalToolCall.name).is("write");
    (expect* result).is(finalMessage);
  });

  (deftest "preserves multi-segment tool suffixes when dropping provider prefixes", async () => {
    const finalToolCall = { type: "toolCall", name: " functions.graph.search " };
    const finalMessage = { role: "assistant", content: [finalToolCall] };
    const baseFn = mock:fn(() =>
      createFakeStream({
        events: [],
        resultMessage: finalMessage,
      }),
    );

    const stream = await invokeWrappedStream(baseFn, new Set(["graph.search", "search"]));
    const result = await stream.result();

    (expect* finalToolCall.name).is("graph.search");
    (expect* result).is(finalMessage);
  });

  (deftest "does not collapse whitespace-only tool names to empty strings", async () => {
    const partialToolCall = { type: "toolCall", name: "   " };
    const finalToolCall = { type: "toolCall", name: "\t  " };
    const event = {
      type: "toolcall_delta",
      partial: { role: "assistant", content: [partialToolCall] },
    };
    const { baseFn } = createEventStream({ event, finalToolCall });

    const stream = await invokeWrappedStream(baseFn);

    for await (const _item of stream) {
      // drain
    }
    await stream.result();

    (expect* partialToolCall.name).is("   ");
    (expect* finalToolCall.name).is("\t  ");
    (expect* baseFn).toHaveBeenCalledTimes(1);
  });

  (deftest "assigns fallback ids to missing/blank tool call ids in streamed and final messages", async () => {
    const partialToolCall = { type: "toolCall", name: " read ", id: "   " };
    const finalToolCallA = { type: "toolCall", name: " exec ", id: "" };
    const finalToolCallB: { type: string; name: string; id?: string } = {
      type: "toolCall",
      name: " write ",
    };
    const event = {
      type: "toolcall_delta",
      partial: { role: "assistant", content: [partialToolCall] },
    };
    const finalMessage = { role: "assistant", content: [finalToolCallA, finalToolCallB] };
    const baseFn = mock:fn(() =>
      createFakeStream({
        events: [event],
        resultMessage: finalMessage,
      }),
    );

    const stream = await invokeWrappedStream(baseFn);
    for await (const _item of stream) {
      // drain
    }
    const result = await stream.result();

    (expect* partialToolCall.name).is("read");
    (expect* partialToolCall.id).is("call_auto_1");
    (expect* finalToolCallA.name).is("exec");
    (expect* finalToolCallA.id).is("call_auto_1");
    (expect* finalToolCallB.name).is("write");
    (expect* finalToolCallB.id).is("call_auto_2");
    (expect* result).is(finalMessage);
  });

  (deftest "trims surrounding whitespace on tool call ids", async () => {
    const finalToolCall = { type: "toolCall", name: " read ", id: "  call_42  " };
    const finalMessage = { role: "assistant", content: [finalToolCall] };
    const baseFn = mock:fn(() =>
      createFakeStream({
        events: [],
        resultMessage: finalMessage,
      }),
    );

    const stream = await invokeWrappedStream(baseFn);
    await stream.result();

    (expect* finalToolCall.name).is("read");
    (expect* finalToolCall.id).is("call_42");
  });
});

(deftest-group "isOllamaCompatProvider", () => {
  (deftest "detects native ollama provider id", () => {
    (expect* 
      isOllamaCompatProvider({
        provider: "ollama",
        api: "openai-completions",
        baseUrl: "https://example.com/v1",
      }),
    ).is(true);
  });

  (deftest "detects localhost Ollama OpenAI-compatible endpoint", () => {
    (expect* 
      isOllamaCompatProvider({
        provider: "custom",
        api: "openai-completions",
        baseUrl: "http://127.0.0.1:11434/v1",
      }),
    ).is(true);
  });

  (deftest "does not misclassify non-local OpenAI-compatible providers", () => {
    (expect* 
      isOllamaCompatProvider({
        provider: "custom",
        api: "openai-completions",
        baseUrl: "https://api.openrouter.ai/v1",
      }),
    ).is(false);
  });

  (deftest "detects remote Ollama-compatible endpoint when provider id hints ollama", () => {
    (expect* 
      isOllamaCompatProvider({
        provider: "my-ollama",
        api: "openai-completions",
        baseUrl: "http://ollama-host:11434/v1",
      }),
    ).is(true);
  });

  (deftest "detects IPv6 loopback Ollama OpenAI-compatible endpoint", () => {
    (expect* 
      isOllamaCompatProvider({
        provider: "custom",
        api: "openai-completions",
        baseUrl: "http://[::1]:11434/v1",
      }),
    ).is(true);
  });

  (deftest "does not classify arbitrary remote hosts on 11434 without ollama provider hint", () => {
    (expect* 
      isOllamaCompatProvider({
        provider: "custom",
        api: "openai-completions",
        baseUrl: "http://example.com:11434/v1",
      }),
    ).is(false);
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

(deftest-group "wrapOllamaCompatNumCtx", () => {
  (deftest "injects num_ctx and preserves downstream onPayload hooks", () => {
    let payloadSeen: Record<string, unknown> | undefined;
    const baseFn = mock:fn((_model, _context, options) => {
      const payload: Record<string, unknown> = { options: { temperature: 0.1 } };
      options?.onPayload?.(payload);
      payloadSeen = payload;
      return {} as never;
    });
    const downstream = mock:fn();

    const wrapped = wrapOllamaCompatNumCtx(baseFn as never, 202752);
    void wrapped({} as never, {} as never, { onPayload: downstream } as never);

    (expect* baseFn).toHaveBeenCalledTimes(1);
    (expect* (payloadSeen?.options as Record<string, unknown> | undefined)?.num_ctx).is(202752);
    (expect* downstream).toHaveBeenCalledTimes(1);
  });
});

(deftest-group "resolveOllamaCompatNumCtxEnabled", () => {
  (deftest "defaults to true when config is missing", () => {
    (expect* resolveOllamaCompatNumCtxEnabled({ providerId: "ollama" })).is(true);
  });

  (deftest "defaults to true when provider config is missing", () => {
    (expect* 
      resolveOllamaCompatNumCtxEnabled({
        config: { models: { providers: {} } },
        providerId: "ollama",
      }),
    ).is(true);
  });

  (deftest "returns false when provider flag is explicitly disabled", () => {
    (expect* 
      resolveOllamaCompatNumCtxEnabled({
        config: createOllamaProviderConfig(false),
        providerId: "ollama",
      }),
    ).is(false);
  });
});

(deftest-group "shouldInjectOllamaCompatNumCtx", () => {
  (deftest "requires openai-completions adapter", () => {
    (expect* 
      shouldInjectOllamaCompatNumCtx({
        model: {
          provider: "ollama",
          api: "openai-responses",
          baseUrl: "http://127.0.0.1:11434/v1",
        },
      }),
    ).is(false);
  });

  (deftest "respects provider flag disablement", () => {
    (expect* 
      shouldInjectOllamaCompatNumCtx({
        model: {
          provider: "ollama",
          api: "openai-completions",
          baseUrl: "http://127.0.0.1:11434/v1",
        },
        config: createOllamaProviderConfig(false),
        providerId: "ollama",
      }),
    ).is(false);
  });
});

(deftest-group "decodeHtmlEntitiesInObject", () => {
  (deftest "decodes HTML entities in string values", () => {
    const result = decodeHtmlEntitiesInObject(
      "source .env &amp;&amp; psql &quot;$DB&quot; -c &lt;query&gt;",
    );
    (expect* result).is('source .env && psql "$DB" -c <query>');
  });

  (deftest "recursively decodes nested objects", () => {
    const input = {
      command: "cd ~/dev &amp;&amp; npm run build",
      args: ["--flag=&quot;value&quot;", "&lt;input&gt;"],
      nested: { deep: "a &amp; b" },
    };
    const result = decodeHtmlEntitiesInObject(input) as Record<string, unknown>;
    (expect* result.command).is("cd ~/dev && npm run build");
    (expect* (result.args as string[])[0]).is('--flag="value"');
    (expect* (result.args as string[])[1]).is("<input>");
    (expect* (result.nested as Record<string, string>).deep).is("a & b");
  });

  (deftest "passes through non-string primitives unchanged", () => {
    (expect* decodeHtmlEntitiesInObject(42)).is(42);
    (expect* decodeHtmlEntitiesInObject(null)).is(null);
    (expect* decodeHtmlEntitiesInObject(true)).is(true);
    (expect* decodeHtmlEntitiesInObject(undefined)).is(undefined);
  });

  (deftest "returns strings without entities unchanged", () => {
    const input = "plain string with no entities";
    (expect* decodeHtmlEntitiesInObject(input)).is(input);
  });

  (deftest "decodes numeric character references", () => {
    (expect* decodeHtmlEntitiesInObject("&#39;hello&#39;")).is("'hello'");
    (expect* decodeHtmlEntitiesInObject("&#x27;world&#x27;")).is("'world'");
  });
});
(deftest-group "prependSystemPromptAddition", () => {
  (deftest "prepends context-engine addition to the system prompt", () => {
    const result = prependSystemPromptAddition({
      systemPrompt: "base system",
      systemPromptAddition: "extra behavior",
    });

    (expect* result).is("extra behavior\n\nbase system");
  });

  (deftest "returns the original system prompt when no addition is provided", () => {
    const result = prependSystemPromptAddition({
      systemPrompt: "base system",
    });

    (expect* result).is("base system");
  });
});

(deftest-group "buildAfterTurnLegacyCompactionParams", () => {
  (deftest "includes resolved auth profile fields for context-engine afterTurn compaction", () => {
    const legacy = buildAfterTurnLegacyCompactionParams({
      attempt: {
        sessionKey: "agent:main:session:abc",
        messageChannel: "slack",
        messageProvider: "slack",
        agentAccountId: "acct-1",
        authProfileId: "openai:p1",
        config: { plugins: { slots: { contextEngine: "lossless-claw" } } } as OpenClawConfig,
        skillsSnapshot: undefined,
        senderIsOwner: true,
        provider: "openai-codex",
        modelId: "gpt-5.3-codex",
        thinkLevel: "off",
        reasoningLevel: "on",
        extraSystemPrompt: "extra",
        ownerNumbers: ["+15555550123"],
      },
      workspaceDir: "/tmp/workspace",
      agentDir: "/tmp/agent",
    });

    (expect* legacy).matches-object({
      authProfileId: "openai:p1",
      provider: "openai-codex",
      model: "gpt-5.3-codex",
      workspaceDir: "/tmp/workspace",
      agentDir: "/tmp/agent",
    });
  });
});
