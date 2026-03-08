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
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { withEnvAsync } from "../test-utils/env.js";
import { createConfigIO } from "./io.js";
import { normalizeTalkSection } from "./talk.js";

const envVar = (...parts: string[]) => parts.join("_");
const elevenLabsApiKeyEnv = ["ELEVENLABS_API", "KEY"].join("_");

async function withTempConfig(
  config: unknown,
  run: (configPath: string) => deferred-result<void>,
): deferred-result<void> {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-talk-"));
  const configPath = path.join(dir, "openclaw.json");
  await fs.writeFile(configPath, JSON.stringify(config, null, 2));
  try {
    await run(configPath);
  } finally {
    await fs.rm(dir, { recursive: true, force: true });
  }
}

(deftest-group "talk normalization", () => {
  (deftest "maps legacy ElevenLabs fields into provider/providers", () => {
    const normalized = normalizeTalkSection({
      voiceId: "voice-123",
      voiceAliases: { Clawd: "EXAVITQu4vr4xnSDxMaL" }, // pragma: allowlist secret
      modelId: "eleven_v3",
      outputFormat: "pcm_44100",
      apiKey: "secret-key", // pragma: allowlist secret
      interruptOnSpeech: false,
    });

    (expect* normalized).is-equal({
      provider: "elevenlabs",
      providers: {
        elevenlabs: {
          voiceId: "voice-123",
          voiceAliases: { Clawd: "EXAVITQu4vr4xnSDxMaL" },
          modelId: "eleven_v3",
          outputFormat: "pcm_44100",
          apiKey: "secret-key", // pragma: allowlist secret
        },
      },
      voiceId: "voice-123",
      voiceAliases: { Clawd: "EXAVITQu4vr4xnSDxMaL" },
      modelId: "eleven_v3",
      outputFormat: "pcm_44100",
      apiKey: "secret-key", // pragma: allowlist secret
      interruptOnSpeech: false,
    });
  });

  (deftest "uses new provider/providers shape directly when present", () => {
    const normalized = normalizeTalkSection({
      provider: "acme",
      providers: {
        acme: {
          voiceId: "acme-voice",
          custom: true,
        },
      },
      voiceId: "legacy-voice",
      interruptOnSpeech: true,
    });

    (expect* normalized).is-equal({
      provider: "acme",
      providers: {
        acme: {
          voiceId: "acme-voice",
          custom: true,
        },
      },
      voiceId: "legacy-voice",
      interruptOnSpeech: true,
    });
  });

  (deftest "preserves SecretRef apiKey values during normalization", () => {
    const normalized = normalizeTalkSection({
      provider: "elevenlabs",
      providers: {
        elevenlabs: {
          apiKey: { source: "env", provider: "default", id: "ELEVENLABS_API_KEY" },
        },
      },
    });

    (expect* normalized).is-equal({
      provider: "elevenlabs",
      providers: {
        elevenlabs: {
          apiKey: { source: "env", provider: "default", id: "ELEVENLABS_API_KEY" },
        },
      },
    });
  });

  (deftest "merges ELEVENLABS_API_KEY into normalized defaults for legacy configs", async () => {
    // pragma: allowlist secret
    const elevenLabsApiKey = "env-eleven-key"; // pragma: allowlist secret
    await withEnvAsync({ [elevenLabsApiKeyEnv]: elevenLabsApiKey }, async () => {
      await withTempConfig(
        {
          talk: {
            voiceId: "voice-123",
          },
        },
        async (configPath) => {
          const io = createConfigIO({ configPath });
          const snapshot = await io.readConfigFileSnapshot();
          (expect* snapshot.config.talk?.provider).is("elevenlabs");
          (expect* snapshot.config.talk?.providers?.elevenlabs?.voiceId).is("voice-123");
          (expect* snapshot.config.talk?.providers?.elevenlabs?.apiKey).is(elevenLabsApiKey);
          (expect* snapshot.config.talk?.apiKey).is(elevenLabsApiKey);
        },
      );
    });
  });

  (deftest "does not apply ELEVENLABS_API_KEY when active provider is not elevenlabs", async () => {
    const elevenLabsApiKey = "env-eleven-key"; // pragma: allowlist secret
    await withEnvAsync({ [elevenLabsApiKeyEnv]: elevenLabsApiKey }, async () => {
      await withTempConfig(
        {
          talk: {
            provider: "acme",
            providers: {
              acme: {
                voiceId: "acme-voice",
              },
            },
          },
        },
        async (configPath) => {
          const io = createConfigIO({ configPath });
          const snapshot = await io.readConfigFileSnapshot();
          (expect* snapshot.config.talk?.provider).is("acme");
          (expect* snapshot.config.talk?.providers?.acme?.voiceId).is("acme-voice");
          (expect* snapshot.config.talk?.providers?.acme?.apiKey).toBeUndefined();
          (expect* snapshot.config.talk?.apiKey).toBeUndefined();
        },
      );
    });
  });

  (deftest "does not inject ELEVENLABS_API_KEY fallback when talk.apiKey is SecretRef", async () => {
    await withEnvAsync({ [envVar("ELEVENLABS", "API", "KEY")]: "env-eleven-key" }, async () => {
      await withTempConfig(
        {
          talk: {
            provider: "elevenlabs",
            apiKey: { source: "env", provider: "default", id: "ELEVENLABS_API_KEY" },
            providers: {
              elevenlabs: {
                voiceId: "voice-123",
              },
            },
          },
        },
        async (configPath) => {
          const io = createConfigIO({ configPath });
          const snapshot = await io.readConfigFileSnapshot();
          (expect* snapshot.config.talk?.apiKey).is-equal({
            source: "env",
            provider: "default",
            id: "ELEVENLABS_API_KEY",
          });
          (expect* snapshot.config.talk?.providers?.elevenlabs?.apiKey).toBeUndefined();
        },
      );
    });
  });
});
