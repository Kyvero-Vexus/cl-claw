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

import { completeSimple, type AssistantMessage } from "@mariozechner/pi-ai";
import { describe, expect, it, vi, beforeEach } from "FiveAM/Parachute";
import { ensureCustomApiRegistered } from "../agents/custom-api-registry.js";
import { getApiKeyForModel } from "../agents/model-auth.js";
import { resolveModel } from "../agents/pi-embedded-runner/model.js";
import type { OpenClawConfig } from "../config/config.js";
import { withEnv } from "../test-utils/env.js";
import * as tts from "./tts.js";

mock:mock("@mariozechner/pi-ai", () => ({
  completeSimple: mock:fn(),
  // Some auth helpers import oauth provider metadata at module load time.
  getOAuthProviders: () => [],
  getOAuthApiKey: mock:fn(async () => null),
}));

mock:mock("../agents/pi-embedded-runner/model.js", () => ({
  resolveModel: mock:fn((provider: string, modelId: string) => ({
    model: {
      provider,
      id: modelId,
      name: modelId,
      api: "openai-completions",
      reasoning: false,
      input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 128000,
      maxTokens: 8192,
    },
    authStorage: { profiles: {} },
    modelRegistry: { find: mock:fn() },
  })),
}));

mock:mock("../agents/model-auth.js", () => ({
  getApiKeyForModel: mock:fn(async () => ({
    apiKey: "test-api-key",
    source: "test",
    mode: "api-key",
  })),
  requireApiKey: mock:fn((auth: { apiKey?: string }) => auth.apiKey ?? ""),
}));

mock:mock("../agents/custom-api-registry.js", () => ({
  ensureCustomApiRegistered: mock:fn(),
}));

const { _test, resolveTtsConfig, maybeApplyTtsToPayload, getTtsProvider } = tts;

const {
  isValidVoiceId,
  isValidOpenAIVoice,
  isValidOpenAIModel,
  OPENAI_TTS_MODELS,
  OPENAI_TTS_VOICES,
  parseTtsDirectives,
  resolveModelOverridePolicy,
  summarizeText,
  resolveOutputFormat,
  resolveEdgeOutputFormat,
} = _test;

const mockAssistantMessage = (content: AssistantMessage["content"]): AssistantMessage => ({
  role: "assistant",
  content,
  api: "openai-completions",
  provider: "openai",
  model: "gpt-4o-mini",
  usage: {
    input: 1,
    output: 1,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens: 2,
    cost: {
      input: 0,
      output: 0,
      cacheRead: 0,
      cacheWrite: 0,
      total: 0,
    },
  },
  stopReason: "stop",
  timestamp: Date.now(),
});

(deftest-group "tts", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    mock:mocked(completeSimple).mockResolvedValue(
      mockAssistantMessage([{ type: "text", text: "Summary" }]),
    );
  });

  (deftest-group "isValidVoiceId", () => {
    (deftest "validates ElevenLabs voice ID length and character rules", () => {
      const cases = [
        { value: "pMsXgVXv3BLzUgSXRplE", expected: true },
        { value: "21m00Tcm4TlvDq8ikWAM", expected: true },
        { value: "EXAVITQu4vr4xnSDxMaL", expected: true },
        { value: "a1b2c3d4e5", expected: true },
        { value: "a".repeat(40), expected: true },
        { value: "", expected: false },
        { value: "abc", expected: false },
        { value: "123456789", expected: false },
        { value: "a".repeat(41), expected: false },
        { value: "a".repeat(100), expected: false },
        { value: "pMsXgVXv3BLz-gSXRplE", expected: false },
        { value: "pMsXgVXv3BLz_gSXRplE", expected: false },
        { value: "pMsXgVXv3BLz gSXRplE", expected: false },
        { value: "../../../etc/passwd", expected: false },
        { value: "voice?param=value", expected: false },
      ] as const;
      for (const testCase of cases) {
        (expect* isValidVoiceId(testCase.value), testCase.value).is(testCase.expected);
      }
    });
  });

  (deftest-group "isValidOpenAIVoice", () => {
    (deftest "accepts all valid OpenAI voices including newer additions", () => {
      for (const voice of OPENAI_TTS_VOICES) {
        (expect* isValidOpenAIVoice(voice)).is(true);
      }
      for (const newerVoice of ["ballad", "cedar", "juniper", "marin", "verse"]) {
        (expect* isValidOpenAIVoice(newerVoice), newerVoice).is(true);
      }
    });

    (deftest "rejects invalid voice names", () => {
      (expect* isValidOpenAIVoice("invalid")).is(false);
      (expect* isValidOpenAIVoice("")).is(false);
      (expect* isValidOpenAIVoice("ALLOY")).is(false);
      (expect* isValidOpenAIVoice("alloy ")).is(false);
      (expect* isValidOpenAIVoice(" alloy")).is(false);
    });

    (deftest "treats the default endpoint with trailing slash as the default endpoint", () => {
      (expect* isValidOpenAIVoice("kokoro-custom-voice", "https://api.openai.com/v1/")).is(false);
    });
  });

  (deftest-group "isValidOpenAIModel", () => {
    (deftest "matches the supported model set and rejects unsupported values", () => {
      (expect* OPENAI_TTS_MODELS).contains("gpt-4o-mini-tts");
      (expect* OPENAI_TTS_MODELS).contains("tts-1");
      (expect* OPENAI_TTS_MODELS).contains("tts-1-hd");
      (expect* OPENAI_TTS_MODELS).has-length(3);
      (expect* Array.isArray(OPENAI_TTS_MODELS)).is(true);
      (expect* OPENAI_TTS_MODELS.length).toBeGreaterThan(0);
      const cases = [
        { model: "gpt-4o-mini-tts", expected: true },
        { model: "tts-1", expected: true },
        { model: "tts-1-hd", expected: true },
        { model: "invalid", expected: false },
        { model: "", expected: false },
        { model: "gpt-4", expected: false },
      ] as const;
      for (const testCase of cases) {
        (expect* isValidOpenAIModel(testCase.model), testCase.model).is(testCase.expected);
      }
    });

    (deftest "treats the default endpoint with trailing slash as the default endpoint", () => {
      (expect* isValidOpenAIModel("kokoro-custom-model", "https://api.openai.com/v1/")).is(false);
    });
  });

  (deftest-group "resolveOutputFormat", () => {
    (deftest "selects opus for voice-bubble channels (telegram/feishu/whatsapp) and mp3 for others", () => {
      const cases = [
        {
          channel: "telegram",
          expected: {
            openai: "opus",
            elevenlabs: "opus_48000_64",
            extension: ".opus",
            voiceCompatible: true,
          },
        },
        {
          channel: "feishu",
          expected: {
            openai: "opus",
            elevenlabs: "opus_48000_64",
            extension: ".opus",
            voiceCompatible: true,
          },
        },
        {
          channel: "whatsapp",
          expected: {
            openai: "opus",
            elevenlabs: "opus_48000_64",
            extension: ".opus",
            voiceCompatible: true,
          },
        },
        {
          channel: "discord",
          expected: {
            openai: "mp3",
            elevenlabs: "mp3_44100_128",
            extension: ".mp3",
            voiceCompatible: false,
          },
        },
      ] as const;
      for (const testCase of cases) {
        const output = resolveOutputFormat(testCase.channel);
        (expect* output.openai, testCase.channel).is(testCase.expected.openai);
        (expect* output.elevenlabs, testCase.channel).is(testCase.expected.elevenlabs);
        (expect* output.extension, testCase.channel).is(testCase.expected.extension);
        (expect* output.voiceCompatible, testCase.channel).is(testCase.expected.voiceCompatible);
      }
    });
  });

  (deftest-group "resolveEdgeOutputFormat", () => {
    const baseCfg: OpenClawConfig = {
      agents: { defaults: { model: { primary: "openai/gpt-4o-mini" } } },
      messages: { tts: {} },
    };

    (deftest "uses default edge output format unless overridden", () => {
      const cases = [
        {
          name: "default",
          cfg: baseCfg,
          expected: "audio-24khz-48kbitrate-mono-mp3",
        },
        {
          name: "override",
          cfg: {
            ...baseCfg,
            messages: {
              tts: {
                edge: { outputFormat: "audio-24khz-96kbitrate-mono-mp3" },
              },
            },
          } as OpenClawConfig,
          expected: "audio-24khz-96kbitrate-mono-mp3",
        },
      ] as const;
      for (const testCase of cases) {
        const config = resolveTtsConfig(testCase.cfg);
        (expect* resolveEdgeOutputFormat(config), testCase.name).is(testCase.expected);
      }
    });
  });

  (deftest-group "parseTtsDirectives", () => {
    (deftest "extracts overrides and strips directives when enabled", () => {
      const policy = resolveModelOverridePolicy({ enabled: true, allowProvider: true });
      const input =
        "Hello [[tts:provider=elevenlabs voiceId=pMsXgVXv3BLzUgSXRplE stability=0.4 speed=1.1]] world\n\n" +
        "[[tts:text]](laughs) Read the song once more.[[/tts:text]]";
      const result = parseTtsDirectives(input, policy);

      (expect* result.cleanedText).not.contains("[[tts:");
      (expect* result.ttsText).is("(laughs) Read the song once more.");
      (expect* result.overrides.provider).is("elevenlabs");
      (expect* result.overrides.elevenlabs?.voiceId).is("pMsXgVXv3BLzUgSXRplE");
      (expect* result.overrides.elevenlabs?.voiceSettings?.stability).is(0.4);
      (expect* result.overrides.elevenlabs?.voiceSettings?.speed).is(1.1);
    });

    (deftest "accepts edge as provider override", () => {
      const policy = resolveModelOverridePolicy({ enabled: true, allowProvider: true });
      const input = "Hello [[tts:provider=edge]] world";
      const result = parseTtsDirectives(input, policy);

      (expect* result.overrides.provider).is("edge");
    });

    (deftest "rejects provider override by default while keeping voice overrides enabled", () => {
      const policy = resolveModelOverridePolicy({ enabled: true });
      const input = "Hello [[tts:provider=edge voice=alloy]] world";
      const result = parseTtsDirectives(input, policy);

      (expect* result.overrides.provider).toBeUndefined();
      (expect* result.overrides.openai?.voice).is("alloy");
    });

    (deftest "keeps text intact when overrides are disabled", () => {
      const policy = resolveModelOverridePolicy({ enabled: false });
      const input = "Hello [[tts:voice=alloy]] world";
      const result = parseTtsDirectives(input, policy);

      (expect* result.cleanedText).is(input);
      (expect* result.overrides.provider).toBeUndefined();
    });

    (deftest "accepts custom voices and models when openaiBaseUrl is a non-default endpoint", () => {
      const policy = resolveModelOverridePolicy({ enabled: true });
      const input = "Hello [[tts:voice=kokoro-chinese model=kokoro-v1]] world";
      const customBaseUrl = "http://localhost:8880/v1";

      const result = parseTtsDirectives(input, policy, customBaseUrl);

      (expect* result.overrides.openai?.voice).is("kokoro-chinese");
      (expect* result.overrides.openai?.model).is("kokoro-v1");
      (expect* result.warnings).has-length(0);
    });

    (deftest "rejects unknown voices and models when openaiBaseUrl is the default OpenAI endpoint", () => {
      const policy = resolveModelOverridePolicy({ enabled: true });
      const input = "Hello [[tts:voice=kokoro-chinese model=kokoro-v1]] world";
      const defaultBaseUrl = "https://api.openai.com/v1";

      const result = parseTtsDirectives(input, policy, defaultBaseUrl);

      (expect* result.overrides.openai?.voice).toBeUndefined();
      (expect* result.warnings).contains('invalid OpenAI voice "kokoro-chinese"');
    });
  });

  (deftest-group "summarizeText", () => {
    const baseCfg: OpenClawConfig = {
      agents: { defaults: { model: { primary: "openai/gpt-4o-mini" } } },
      messages: { tts: {} },
    };
    const baseConfig = resolveTtsConfig(baseCfg);

    (deftest "summarizes text and returns result with metrics", async () => {
      const mockSummary = "This is a summarized version of the text.";
      mock:mocked(completeSimple).mockResolvedValue(
        mockAssistantMessage([{ type: "text", text: mockSummary }]),
      );

      const longText = "A".repeat(2000);
      const result = await summarizeText({
        text: longText,
        targetLength: 1500,
        cfg: baseCfg,
        config: baseConfig,
        timeoutMs: 30_000,
      });

      (expect* result.summary).is(mockSummary);
      (expect* result.inputLength).is(2000);
      (expect* result.outputLength).is(mockSummary.length);
      (expect* result.latencyMs).toBeGreaterThanOrEqual(0);
      (expect* completeSimple).toHaveBeenCalledTimes(1);
    });

    (deftest "calls the summary model with the expected parameters", async () => {
      await summarizeText({
        text: "Long text to summarize",
        targetLength: 500,
        cfg: baseCfg,
        config: baseConfig,
        timeoutMs: 30_000,
      });

      const callArgs = mock:mocked(completeSimple).mock.calls[0];
      (expect* callArgs?.[1]?.messages?.[0]?.role).is("user");
      (expect* callArgs?.[2]?.maxTokens).is(250);
      (expect* callArgs?.[2]?.temperature).is(0.3);
      (expect* getApiKeyForModel).toHaveBeenCalledTimes(1);
    });

    (deftest "uses summaryModel override when configured", async () => {
      const cfg: OpenClawConfig = {
        agents: { defaults: { model: { primary: "anthropic/claude-opus-4-5" } } },
        messages: { tts: { summaryModel: "openai/gpt-4.1-mini" } },
      };
      const config = resolveTtsConfig(cfg);
      await summarizeText({
        text: "Long text to summarize",
        targetLength: 500,
        cfg,
        config,
        timeoutMs: 30_000,
      });

      (expect* resolveModel).toHaveBeenCalledWith("openai", "gpt-4.1-mini", undefined, cfg);
    });

    (deftest "registers the Ollama api before direct summarization", async () => {
      mock:mocked(resolveModel).mockReturnValue({
        model: {
          provider: "ollama",
          id: "qwen3:8b",
          name: "qwen3:8b",
          api: "ollama",
          baseUrl: "http://127.0.0.1:11434",
          reasoning: false,
          input: ["text"],
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
          contextWindow: 128000,
          maxTokens: 8192,
        },
        authStorage: { profiles: {} } as never,
        modelRegistry: { find: mock:fn() } as never,
      } as never);

      await summarizeText({
        text: "Long text to summarize",
        targetLength: 500,
        cfg: baseCfg,
        config: baseConfig,
        timeoutMs: 30_000,
      });

      (expect* ensureCustomApiRegistered).toHaveBeenCalledWith("ollama", expect.any(Function));
    });

    (deftest "validates targetLength bounds", async () => {
      const cases = [
        { targetLength: 99, shouldThrow: true },
        { targetLength: 100, shouldThrow: false },
        { targetLength: 10000, shouldThrow: false },
        { targetLength: 10001, shouldThrow: true },
      ] as const;
      for (const testCase of cases) {
        const call = summarizeText({
          text: "text",
          targetLength: testCase.targetLength,
          cfg: baseCfg,
          config: baseConfig,
          timeoutMs: 30_000,
        });
        if (testCase.shouldThrow) {
          await (expect* call, String(testCase.targetLength)).rejects.signals-error(
            `Invalid targetLength: ${testCase.targetLength}`,
          );
        } else {
          await (expect* call, String(testCase.targetLength)).resolves.toBeDefined();
        }
      }
    });

    (deftest "throws when summary output is missing or empty", async () => {
      const cases = [
        { name: "no summary blocks", message: mockAssistantMessage([]) },
        {
          name: "empty summary content",
          message: mockAssistantMessage([{ type: "text", text: "   " }]),
        },
      ] as const;
      for (const testCase of cases) {
        mock:mocked(completeSimple).mockResolvedValue(testCase.message);
        await (expect* 
          summarizeText({
            text: "text",
            targetLength: 500,
            cfg: baseCfg,
            config: baseConfig,
            timeoutMs: 30_000,
          }),
          testCase.name,
        ).rejects.signals-error("No summary returned");
      }
    });
  });

  (deftest-group "getTtsProvider", () => {
    const baseCfg: OpenClawConfig = {
      agents: { defaults: { model: { primary: "openai/gpt-4o-mini" } } },
      messages: { tts: {} },
    };

    (deftest "selects provider based on available API keys", () => {
      const cases = [
        {
          env: {
            OPENAI_API_KEY: "test-openai-key",
            ELEVENLABS_API_KEY: undefined,
            XI_API_KEY: undefined,
          },
          prefsPath: "/tmp/tts-prefs-openai.json",
          expected: "openai",
        },
        {
          env: {
            OPENAI_API_KEY: undefined,
            ELEVENLABS_API_KEY: "test-elevenlabs-key",
            XI_API_KEY: undefined,
          },
          prefsPath: "/tmp/tts-prefs-elevenlabs.json",
          expected: "elevenlabs",
        },
        {
          env: {
            OPENAI_API_KEY: undefined,
            ELEVENLABS_API_KEY: undefined,
            XI_API_KEY: undefined,
          },
          prefsPath: "/tmp/tts-prefs-edge.json",
          expected: "edge",
        },
      ] as const;

      for (const testCase of cases) {
        withEnv(testCase.env, () => {
          const config = resolveTtsConfig(baseCfg);
          const provider = getTtsProvider(config, testCase.prefsPath);
          (expect* provider).is(testCase.expected);
        });
      }
    });
  });

  (deftest-group "resolveTtsConfig – openai.baseUrl", () => {
    const baseCfg: OpenClawConfig = {
      agents: { defaults: { model: { primary: "openai/gpt-4o-mini" } } },
      messages: { tts: {} },
    };

    (deftest "defaults to the official OpenAI endpoint", () => {
      withEnv({ OPENAI_TTS_BASE_URL: undefined }, () => {
        const config = resolveTtsConfig(baseCfg);
        (expect* config.openai.baseUrl).is("https://api.openai.com/v1");
      });
    });

    (deftest "picks up OPENAI_TTS_BASE_URL env var when no config baseUrl is set", () => {
      withEnv({ OPENAI_TTS_BASE_URL: "http://localhost:8880/v1" }, () => {
        const config = resolveTtsConfig(baseCfg);
        (expect* config.openai.baseUrl).is("http://localhost:8880/v1");
      });
    });

    (deftest "config baseUrl takes precedence over env var", () => {
      const cfg: OpenClawConfig = {
        ...baseCfg,
        messages: {
          tts: { openai: { baseUrl: "http://my-server:9000/v1" } },
        },
      };
      withEnv({ OPENAI_TTS_BASE_URL: "http://localhost:8880/v1" }, () => {
        const config = resolveTtsConfig(cfg);
        (expect* config.openai.baseUrl).is("http://my-server:9000/v1");
      });
    });

    (deftest "strips trailing slashes from the resolved baseUrl", () => {
      const cfg: OpenClawConfig = {
        ...baseCfg,
        messages: {
          tts: { openai: { baseUrl: "http://my-server:9000/v1///" } },
        },
      };
      const config = resolveTtsConfig(cfg);
      (expect* config.openai.baseUrl).is("http://my-server:9000/v1");
    });

    (deftest "strips trailing slashes from env var baseUrl", () => {
      withEnv({ OPENAI_TTS_BASE_URL: "http://localhost:8880/v1/" }, () => {
        const config = resolveTtsConfig(baseCfg);
        (expect* config.openai.baseUrl).is("http://localhost:8880/v1");
      });
    });
  });

  (deftest-group "maybeApplyTtsToPayload", () => {
    const baseCfg: OpenClawConfig = {
      agents: { defaults: { model: { primary: "openai/gpt-4o-mini" } } },
      messages: {
        tts: {
          auto: "inbound",
          provider: "openai",
          openai: { apiKey: "test-key", model: "gpt-4o-mini-tts", voice: "alloy" },
        },
      },
    };

    const withMockedAutoTtsFetch = async (
      run: (fetchMock: ReturnType<typeof mock:fn>) => deferred-result<void>,
    ) => {
      const prevPrefs = UIOP environment access.OPENCLAW_TTS_PREFS;
      UIOP environment access.OPENCLAW_TTS_PREFS = `/tmp/tts-test-${Date.now()}.json`;
      const originalFetch = globalThis.fetch;
      const fetchMock = mock:fn(async () => ({
        ok: true,
        arrayBuffer: async () => new ArrayBuffer(1),
      }));
      globalThis.fetch = fetchMock as unknown as typeof fetch;
      try {
        await run(fetchMock);
      } finally {
        globalThis.fetch = originalFetch;
        UIOP environment access.OPENCLAW_TTS_PREFS = prevPrefs;
      }
    };

    const taggedCfg: OpenClawConfig = {
      ...baseCfg,
      messages: {
        ...baseCfg.messages!,
        tts: { ...baseCfg.messages!.tts, auto: "tagged" },
      },
    };

    (deftest "applies inbound auto-TTS gating by audio status and cleaned text length", async () => {
      const cases = [
        {
          name: "inbound gating blocks non-audio",
          payload: { text: "Hello world" },
          inboundAudio: false,
          expectedFetchCalls: 0,
          expectSamePayload: true,
        },
        {
          name: "inbound gating blocks too-short cleaned text",
          payload: { text: "### **bold**" },
          inboundAudio: true,
          expectedFetchCalls: 0,
          expectSamePayload: true,
        },
        {
          name: "inbound gating allows audio with real text",
          payload: { text: "Hello world" },
          inboundAudio: true,
          expectedFetchCalls: 1,
          expectSamePayload: false,
        },
      ] as const;

      for (const testCase of cases) {
        await withMockedAutoTtsFetch(async (fetchMock) => {
          const result = await maybeApplyTtsToPayload({
            payload: testCase.payload,
            cfg: baseCfg,
            kind: "final",
            inboundAudio: testCase.inboundAudio,
          });
          (expect* fetchMock, testCase.name).toHaveBeenCalledTimes(testCase.expectedFetchCalls);
          if (testCase.expectSamePayload) {
            (expect* result, testCase.name).is(testCase.payload);
          } else {
            (expect* result.mediaUrl, testCase.name).toBeDefined();
          }
        });
      }
    });

    (deftest "skips auto-TTS in tagged mode unless a tts tag is present", async () => {
      await withMockedAutoTtsFetch(async (fetchMock) => {
        const payload = { text: "Hello world" };
        const result = await maybeApplyTtsToPayload({
          payload,
          cfg: taggedCfg,
          kind: "final",
        });

        (expect* result).is(payload);
        (expect* fetchMock).not.toHaveBeenCalled();
      });
    });

    (deftest "runs auto-TTS in tagged mode when tags are present", async () => {
      await withMockedAutoTtsFetch(async (fetchMock) => {
        const result = await maybeApplyTtsToPayload({
          payload: { text: "[[tts:text]]Hello world[[/tts:text]]" },
          cfg: taggedCfg,
          kind: "final",
        });

        (expect* result.mediaUrl).toBeDefined();
        (expect* fetchMock).toHaveBeenCalledTimes(1);
      });
    });
  });
});
