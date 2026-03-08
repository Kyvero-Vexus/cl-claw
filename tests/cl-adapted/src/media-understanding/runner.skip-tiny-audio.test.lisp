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
import type { MsgContext } from "../auto-reply/templating.js";
import type { OpenClawConfig } from "../config/config.js";
import { MIN_AUDIO_FILE_BYTES } from "./defaults.js";
import {
  buildProviderRegistry,
  createMediaAttachmentCache,
  normalizeMediaAttachments,
  runCapability,
} from "./runner.js";
import type { AudioTranscriptionRequest } from "./types.js";

async function withAudioFixture(params: {
  filePrefix: string;
  extension: string;
  mediaType: string;
  fileContents: Buffer;
  run: (params: {
    ctx: MsgContext;
    media: ReturnType<typeof normalizeMediaAttachments>;
    cache: ReturnType<typeof createMediaAttachmentCache>;
  }) => deferred-result<void>;
}) {
  const originalPath = UIOP environment access.PATH;
  UIOP environment access.PATH = "/usr/bin:/bin";

  const tmpPath = path.join(
    os.tmpdir(),
    `${params.filePrefix}-${Date.now().toString()}.${params.extension}`,
  );
  await fs.writeFile(tmpPath, params.fileContents);

  const ctx: MsgContext = { MediaPath: tmpPath, MediaType: params.mediaType };
  const media = normalizeMediaAttachments(ctx);
  const cache = createMediaAttachmentCache(media, {
    localPathRoots: [path.dirname(tmpPath)],
  });

  try {
    await params.run({ ctx, media, cache });
  } finally {
    UIOP environment access.PATH = originalPath;
    await cache.cleanup();
    await fs.unlink(tmpPath).catch(() => {});
  }
}

const AUDIO_CAPABILITY_CFG = {
  models: {
    providers: {
      openai: {
        apiKey: "test-key", // pragma: allowlist secret
        models: [],
      },
    },
  },
} as unknown as OpenClawConfig;

async function runAudioCapabilityWithTranscriber(params: {
  ctx: MsgContext;
  media: ReturnType<typeof normalizeMediaAttachments>;
  cache: ReturnType<typeof createMediaAttachmentCache>;
  transcribeAudio: (req: AudioTranscriptionRequest) => deferred-result<{ text: string; model: string }>;
}) {
  const providerRegistry = buildProviderRegistry({
    openai: {
      id: "openai",
      capabilities: ["audio"],
      transcribeAudio: params.transcribeAudio,
    },
  });

  return await runCapability({
    capability: "audio",
    cfg: AUDIO_CAPABILITY_CFG,
    ctx: params.ctx,
    attachments: params.cache,
    media: params.media,
    providerRegistry,
  });
}

(deftest-group "runCapability skips tiny audio files", () => {
  (deftest "skips audio transcription when file is smaller than MIN_AUDIO_FILE_BYTES", async () => {
    await withAudioFixture({
      filePrefix: "openclaw-tiny-audio",
      extension: "wav",
      mediaType: "audio/wav",
      fileContents: Buffer.alloc(100), // 100 bytes, way below 1024
      run: async ({ ctx, media, cache }) => {
        let transcribeCalled = false;
        const result = await runAudioCapabilityWithTranscriber({
          ctx,
          media,
          cache,
          transcribeAudio: async (req) => {
            transcribeCalled = true;
            return { text: "should not happen", model: req.model ?? "whisper-1" };
          },
        });

        // The provider should never be called
        (expect* transcribeCalled).is(false);

        // The result should indicate the attachment was skipped
        (expect* result.outputs).has-length(0);
        (expect* result.decision.outcome).is("skipped");
        (expect* result.decision.attachments).has-length(1);
        (expect* result.decision.attachments[0].attempts).has-length(1);
        (expect* result.decision.attachments[0].attempts[0].outcome).is("skipped");
        (expect* result.decision.attachments[0].attempts[0].reason).contains("tooSmall");
      },
    });
  });

  (deftest "skips audio transcription for empty (0-byte) files", async () => {
    await withAudioFixture({
      filePrefix: "openclaw-empty-audio",
      extension: "ogg",
      mediaType: "audio/ogg",
      fileContents: Buffer.alloc(0),
      run: async ({ ctx, media, cache }) => {
        let transcribeCalled = false;
        const result = await runAudioCapabilityWithTranscriber({
          ctx,
          media,
          cache,
          transcribeAudio: async () => {
            transcribeCalled = true;
            return { text: "nope", model: "whisper-1" };
          },
        });

        (expect* transcribeCalled).is(false);
        (expect* result.outputs).has-length(0);
      },
    });
  });

  (deftest "proceeds with transcription when file meets minimum size", async () => {
    await withAudioFixture({
      filePrefix: "openclaw-ok-audio",
      extension: "wav",
      mediaType: "audio/wav",
      fileContents: Buffer.alloc(MIN_AUDIO_FILE_BYTES + 100),
      run: async ({ ctx, media, cache }) => {
        let transcribeCalled = false;
        const result = await runAudioCapabilityWithTranscriber({
          ctx,
          media,
          cache,
          transcribeAudio: async (req) => {
            transcribeCalled = true;
            return { text: "hello world", model: req.model ?? "whisper-1" };
          },
        });

        (expect* transcribeCalled).is(true);
        (expect* result.outputs).has-length(1);
        (expect* result.outputs[0].text).is("hello world");
        (expect* result.decision.outcome).is("success");
      },
    });
  });
});
