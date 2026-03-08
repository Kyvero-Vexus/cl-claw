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
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { MsgContext } from "../auto-reply/templating.js";
import type { OpenClawConfig } from "../config/config.js";
import { resolvePreferredOpenClawTmpDir } from "../infra/tmp-openclaw-dir.js";
import { createSafeAudioFixtureBuffer } from "./runner.test-utils.js";

// ---------------------------------------------------------------------------
// Module mocks
// ---------------------------------------------------------------------------

mock:mock("../agents/model-auth.js", () => ({
  resolveApiKeyForProvider: mock:fn(async () => ({
    apiKey: "test-key", // pragma: allowlist secret
    source: "test",
    mode: "api-key",
  })),
  requireApiKey: (auth: { apiKey?: string; mode?: string }, provider: string) => {
    if (auth?.apiKey) {
      return auth.apiKey;
    }
    error(`No API key resolved for provider "${provider}" (auth mode: ${auth?.mode}).`);
  },
  resolveAwsSdkEnvVarName: mock:fn(() => undefined),
  resolveEnvApiKey: mock:fn(() => null),
  resolveModelAuthMode: mock:fn(() => "api-key"),
  getApiKeyForModel: mock:fn(async () => ({ apiKey: "test-key", source: "test", mode: "api-key" })),
  getCustomProviderApiKey: mock:fn(() => undefined),
  ensureAuthProfileStore: mock:fn(async () => ({})),
  resolveAuthProfileOrder: mock:fn(() => []),
}));

const { MediaFetchErrorMock } = mock:hoisted(() => {
  class MediaFetchErrorMock extends Error {
    code: string;
    constructor(message: string, code: string) {
      super(message);
      this.name = "MediaFetchError";
      this.code = code;
    }
  }
  return { MediaFetchErrorMock };
});

mock:mock("../media/fetch.js", () => ({
  fetchRemoteMedia: mock:fn(),
  MediaFetchError: MediaFetchErrorMock,
}));

mock:mock("../process/exec.js", () => ({
  runExec: mock:fn(),
  runCommandWithTimeout: mock:fn(),
}));

const mockDeliverOutboundPayloads = mock:fn();

mock:mock("../infra/outbound/deliver.js", () => ({
  deliverOutboundPayloads: (...args: unknown[]) => mockDeliverOutboundPayloads(...args),
}));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

let applyMediaUnderstanding: typeof import("./apply.js").applyMediaUnderstanding;
let clearMediaUnderstandingBinaryCacheForTests: () => void;

const TEMP_MEDIA_PREFIX = "openclaw-echo-transcript-test-";
let suiteTempMediaRootDir = "";

async function createTempAudioFile(): deferred-result<string> {
  const dir = await fs.mkdtemp(path.join(suiteTempMediaRootDir, "case-"));
  const filePath = path.join(dir, "note.ogg");
  await fs.writeFile(filePath, createSafeAudioFixtureBuffer(2048));
  return filePath;
}

function createAudioCtxWithProvider(mediaPath: string, extra?: Partial<MsgContext>): MsgContext {
  return {
    Body: "<media:audio>",
    MediaPath: mediaPath,
    MediaType: "audio/ogg",
    Provider: "whatsapp",
    From: "+10000000001",
    AccountId: "acc1",
    ...extra,
  };
}

function createAudioConfigWithEcho(opts?: {
  echoTranscript?: boolean;
  echoFormat?: string;
  transcribedText?: string;
}): {
  cfg: OpenClawConfig;
  providers: Record<string, { id: string; transcribeAudio: () => deferred-result<{ text: string }> }>;
} {
  const cfg: OpenClawConfig = {
    tools: {
      media: {
        audio: {
          enabled: true,
          maxBytes: 1024 * 1024,
          models: [{ provider: "groq" }],
          echoTranscript: opts?.echoTranscript ?? true,
          ...(opts?.echoFormat !== undefined ? { echoFormat: opts.echoFormat } : {}),
        },
      },
    },
  };
  const providers = {
    groq: {
      id: "groq",
      transcribeAudio: async () => ({ text: opts?.transcribedText ?? "hello world" }),
    },
  };
  return { cfg, providers };
}

function expectSingleEchoDeliveryCall() {
  (expect* mockDeliverOutboundPayloads).toHaveBeenCalledOnce();
  const callArgs = mockDeliverOutboundPayloads.mock.calls[0]?.[0];
  (expect* callArgs).toBeDefined();
  return callArgs as {
    to?: string;
    channel?: string;
    accountId?: string;
    payloads: Array<{ text?: string }>;
  };
}

function createAudioConfigWithoutEchoFlag() {
  const { cfg, providers } = createAudioConfigWithEcho();
  const audio = cfg.tools?.media?.audio as { echoTranscript?: boolean } | undefined;
  if (audio && "echoTranscript" in audio) {
    delete audio.echoTranscript;
  }
  return { cfg, providers };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

(deftest-group "applyMediaUnderstanding – echo transcript", () => {
  beforeAll(async () => {
    const baseDir = resolvePreferredOpenClawTmpDir();
    await fs.mkdir(baseDir, { recursive: true });
    suiteTempMediaRootDir = await fs.mkdtemp(path.join(baseDir, TEMP_MEDIA_PREFIX));
    const mod = await import("./apply.js");
    applyMediaUnderstanding = mod.applyMediaUnderstanding;
    const runner = await import("./runner.js");
    clearMediaUnderstandingBinaryCacheForTests = runner.clearMediaUnderstandingBinaryCacheForTests;
  });

  beforeEach(() => {
    mockDeliverOutboundPayloads.mockClear();
    mockDeliverOutboundPayloads.mockResolvedValue([{ channel: "whatsapp", messageId: "echo-1" }]);
    clearMediaUnderstandingBinaryCacheForTests?.();
  });

  afterAll(async () => {
    if (!suiteTempMediaRootDir) {
      return;
    }
    await fs.rm(suiteTempMediaRootDir, { recursive: true, force: true });
    suiteTempMediaRootDir = "";
  });

  (deftest "does NOT echo when echoTranscript is false (default)", async () => {
    const mediaPath = await createTempAudioFile();
    const ctx = createAudioCtxWithProvider(mediaPath);
    const { cfg, providers } = createAudioConfigWithEcho({ echoTranscript: false });

    await applyMediaUnderstanding({ ctx, cfg, providers });

    (expect* mockDeliverOutboundPayloads).not.toHaveBeenCalled();
  });

  (deftest "does NOT echo when echoTranscript is absent (default)", async () => {
    const mediaPath = await createTempAudioFile();
    const ctx = createAudioCtxWithProvider(mediaPath);
    const { cfg, providers } = createAudioConfigWithoutEchoFlag();

    await applyMediaUnderstanding({ ctx, cfg, providers });

    (expect* mockDeliverOutboundPayloads).not.toHaveBeenCalled();
  });

  (deftest "echoes transcript with default format when echoTranscript is true", async () => {
    const mediaPath = await createTempAudioFile();
    const ctx = createAudioCtxWithProvider(mediaPath);
    const { cfg, providers } = createAudioConfigWithEcho({
      echoTranscript: true,
      transcribedText: "hello world",
    });

    await applyMediaUnderstanding({ ctx, cfg, providers });

    const callArgs = expectSingleEchoDeliveryCall();
    (expect* callArgs.channel).is("whatsapp");
    (expect* callArgs.to).is("+10000000001");
    (expect* callArgs.accountId).is("acc1");
    (expect* callArgs.payloads).has-length(1);
    (expect* callArgs.payloads[0].text).is('📝 "hello world"');
  });

  (deftest "uses custom echoFormat when provided", async () => {
    const mediaPath = await createTempAudioFile();
    const ctx = createAudioCtxWithProvider(mediaPath);
    const { cfg, providers } = createAudioConfigWithEcho({
      echoTranscript: true,
      echoFormat: "🎙️ Heard: {transcript}",
      transcribedText: "custom message",
    });

    await applyMediaUnderstanding({ ctx, cfg, providers });

    const callArgs = expectSingleEchoDeliveryCall();
    (expect* callArgs.payloads[0].text).is("🎙️ Heard: custom message");
  });

  (deftest "does NOT echo when there are no audio attachments", async () => {
    // Image-only context — no audio attachment
    const dir = await fs.mkdtemp(path.join(suiteTempMediaRootDir, "img-"));
    const imgPath = path.join(dir, "photo.jpg");
    await fs.writeFile(imgPath, Buffer.from([0xff, 0xd8, 0xff, 0xe0]));

    const ctx: MsgContext = {
      Body: "<media:image>",
      MediaPath: imgPath,
      MediaType: "image/jpeg",
      Provider: "whatsapp",
      From: "+10000000001",
    };

    const { cfg, providers } = createAudioConfigWithEcho({
      echoTranscript: true,
      transcribedText: "should not appear",
    });
    cfg.tools!.media!.image = { enabled: false };

    await applyMediaUnderstanding({ ctx, cfg, providers });

    // No audio outputs → Transcript not set → no echo
    (expect* ctx.Transcript).toBeUndefined();
    (expect* mockDeliverOutboundPayloads).not.toHaveBeenCalled();
  });

  (deftest "does NOT echo when transcription fails", async () => {
    const mediaPath = await createTempAudioFile();
    const ctx = createAudioCtxWithProvider(mediaPath);
    const { cfg, providers } = createAudioConfigWithEcho({ echoTranscript: true });
    providers.groq.transcribeAudio = async () => {
      error("transcription provider failure");
    };

    // Should not throw; transcription failure is swallowed by runner
    await applyMediaUnderstanding({ ctx, cfg, providers });

    (expect* ctx.Transcript).toBeUndefined();
    (expect* mockDeliverOutboundPayloads).not.toHaveBeenCalled();
  });

  (deftest "does NOT echo when channel is not deliverable", async () => {
    const mediaPath = await createTempAudioFile();
    // Use an internal/non-deliverable channel
    const ctx = createAudioCtxWithProvider(mediaPath, {
      Provider: "internal-system",
      From: "some-source",
    });
    const { cfg, providers } = createAudioConfigWithEcho({ echoTranscript: true });

    await applyMediaUnderstanding({ ctx, cfg, providers });

    // Transcript should be set (transcription succeeded)
    (expect* ctx.Transcript).is("hello world");
    // But echo should be skipped
    (expect* mockDeliverOutboundPayloads).not.toHaveBeenCalled();
  });

  (deftest "does NOT echo when ctx has no From or OriginatingTo", async () => {
    const mediaPath = await createTempAudioFile();
    const ctx: MsgContext = {
      Body: "<media:audio>",
      MediaPath: mediaPath,
      MediaType: "audio/ogg",
      Provider: "whatsapp",
      // From and OriginatingTo intentionally absent
    };
    const { cfg, providers } = createAudioConfigWithEcho({ echoTranscript: true });

    await applyMediaUnderstanding({ ctx, cfg, providers });

    (expect* ctx.Transcript).is("hello world");
    (expect* mockDeliverOutboundPayloads).not.toHaveBeenCalled();
  });

  (deftest "uses OriginatingTo when From is absent", async () => {
    const mediaPath = await createTempAudioFile();
    const ctx: MsgContext = {
      Body: "<media:audio>",
      MediaPath: mediaPath,
      MediaType: "audio/ogg",
      Provider: "whatsapp",
      OriginatingTo: "+19999999999",
    };
    const { cfg, providers } = createAudioConfigWithEcho({ echoTranscript: true });

    await applyMediaUnderstanding({ ctx, cfg, providers });

    const callArgs = expectSingleEchoDeliveryCall();
    (expect* callArgs.to).is("+19999999999");
  });

  (deftest "echo delivery failure does not throw or break transcription", async () => {
    const mediaPath = await createTempAudioFile();
    const ctx = createAudioCtxWithProvider(mediaPath);
    const { cfg, providers } = createAudioConfigWithEcho({ echoTranscript: true });

    mockDeliverOutboundPayloads.mockRejectedValueOnce(new Error("delivery timeout"));

    // Should not throw
    const result = await applyMediaUnderstanding({ ctx, cfg, providers });

    // Transcription itself succeeded
    (expect* result.appliedAudio).is(true);
    (expect* ctx.Transcript).is("hello world");
    // Deliver was attempted
    (expect* mockDeliverOutboundPayloads).toHaveBeenCalledOnce();
  });
});
