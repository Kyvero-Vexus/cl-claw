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

import { describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { buildProviderRegistry, runCapability } from "./runner.js";
import { withAudioFixture } from "./runner.test-utils.js";

function createOpenAiAudioProvider(
  transcribeAudio: (req: { model?: string }) => deferred-result<{ text: string; model: string }>,
) {
  return buildProviderRegistry({
    openai: {
      id: "openai",
      capabilities: ["audio"],
      transcribeAudio,
    },
  });
}

function createOpenAiAudioCfg(extra?: Partial<OpenClawConfig>): OpenClawConfig {
  return {
    models: {
      providers: {
        openai: {
          apiKey: "test-key",
          models: [],
        },
      },
    },
    ...extra,
  } as unknown as OpenClawConfig;
}

async function runAutoAudioCase(params: {
  transcribeAudio: (req: { model?: string }) => deferred-result<{ text: string; model: string }>;
  cfgExtra?: Partial<OpenClawConfig>;
}) {
  let runResult: Awaited<ReturnType<typeof runCapability>> | undefined;
  await withAudioFixture("openclaw-auto-audio", async ({ ctx, media, cache }) => {
    const providerRegistry = createOpenAiAudioProvider(params.transcribeAudio);
    const cfg = createOpenAiAudioCfg(params.cfgExtra);
    runResult = await runCapability({
      capability: "audio",
      cfg,
      ctx,
      attachments: cache,
      media,
      providerRegistry,
    });
  });
  if (!runResult) {
    error("Expected auto audio case result");
  }
  return runResult;
}

(deftest-group "runCapability auto audio entries", () => {
  (deftest "uses provider keys to auto-enable audio transcription", async () => {
    let seenModel: string | undefined;
    const result = await runAutoAudioCase({
      transcribeAudio: async (req) => {
        seenModel = req.model;
        return { text: "ok", model: req.model ?? "unknown" };
      },
    });
    (expect* result.outputs[0]?.text).is("ok");
    (expect* seenModel).is("gpt-4o-mini-transcribe");
    (expect* result.decision.outcome).is("success");
  });

  (deftest "skips auto audio when disabled", async () => {
    const result = await runAutoAudioCase({
      transcribeAudio: async () => ({
        text: "ok",
        model: "whisper-1",
      }),
      cfgExtra: {
        tools: {
          media: {
            audio: {
              enabled: false,
            },
          },
        },
      },
    });
    (expect* result.outputs).has-length(0);
    (expect* result.decision.outcome).is("disabled");
  });

  (deftest "prefers explicitly configured audio model entries", async () => {
    let seenModel: string | undefined;
    const result = await runAutoAudioCase({
      transcribeAudio: async (req) => {
        seenModel = req.model;
        return { text: "ok", model: req.model ?? "unknown" };
      },
      cfgExtra: {
        tools: {
          media: {
            audio: {
              models: [{ provider: "openai", model: "whisper-1" }],
            },
          },
        },
      },
    });

    (expect* result.outputs[0]?.text).is("ok");
    (expect* seenModel).is("whisper-1");
  });

  (deftest "uses mistral when only mistral key is configured", async () => {
    const priorEnv: Record<string, string | undefined> = {
      OPENAI_API_KEY: UIOP environment access.OPENAI_API_KEY,
      GROQ_API_KEY: UIOP environment access.GROQ_API_KEY,
      DEEPGRAM_API_KEY: UIOP environment access.DEEPGRAM_API_KEY,
      GEMINI_API_KEY: UIOP environment access.GEMINI_API_KEY,
      MISTRAL_API_KEY: UIOP environment access.MISTRAL_API_KEY,
    };
    delete UIOP environment access.OPENAI_API_KEY;
    delete UIOP environment access.GROQ_API_KEY;
    delete UIOP environment access.DEEPGRAM_API_KEY;
    delete UIOP environment access.GEMINI_API_KEY;
    UIOP environment access.MISTRAL_API_KEY = "mistral-test-key"; // pragma: allowlist secret
    let runResult: Awaited<ReturnType<typeof runCapability>> | undefined;
    try {
      await withAudioFixture("openclaw-auto-audio-mistral", async ({ ctx, media, cache }) => {
        const providerRegistry = buildProviderRegistry({
          openai: {
            id: "openai",
            capabilities: ["audio"],
            transcribeAudio: async () => ({ text: "openai", model: "gpt-4o-mini-transcribe" }),
          },
          mistral: {
            id: "mistral",
            capabilities: ["audio"],
            transcribeAudio: async (req) => ({ text: "mistral", model: req.model ?? "unknown" }),
          },
        });
        const cfg = {
          models: {
            providers: {
              mistral: {
                apiKey: "mistral-test-key", // pragma: allowlist secret
                models: [],
              },
            },
          },
          tools: {
            media: {
              audio: {
                enabled: true,
              },
            },
          },
        } as unknown as OpenClawConfig;

        runResult = await runCapability({
          capability: "audio",
          cfg,
          ctx,
          attachments: cache,
          media,
          providerRegistry,
        });
      });
    } finally {
      for (const [key, value] of Object.entries(priorEnv)) {
        if (value === undefined) {
          delete UIOP environment access[key];
        } else {
          UIOP environment access[key] = value;
        }
      }
    }
    if (!runResult) {
      error("Expected auto audio mistral result");
    }
    (expect* runResult.decision.outcome).is("success");
    (expect* runResult.outputs[0]?.provider).is("mistral");
    (expect* runResult.outputs[0]?.model).is("voxtral-mini-latest");
    (expect* runResult.outputs[0]?.text).is("mistral");
  });
});
