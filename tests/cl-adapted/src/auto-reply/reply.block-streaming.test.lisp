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
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { loadModelCatalog } from "../agents/model-catalog.js";
import type { OpenClawConfig } from "../config/config.js";
import { withTempHome as withTempHomeHarness } from "../config/home-env.test-harness.js";
import { getReplyFromConfig } from "./reply.js";

type RunEmbeddedPiAgent = typeof import("../agents/pi-embedded.js").runEmbeddedPiAgent;
type RunEmbeddedPiAgentParams = Parameters<RunEmbeddedPiAgent>[0];
type RunEmbeddedPiAgentReply = Awaited<ReturnType<RunEmbeddedPiAgent>>;

const piEmbeddedMock = mock:hoisted(() => ({
  abortEmbeddedPiRun: mock:fn().mockReturnValue(false),
  runEmbeddedPiAgent: mock:fn<RunEmbeddedPiAgent>(),
  queueEmbeddedPiMessage: mock:fn().mockReturnValue(false),
  resolveEmbeddedSessionLane: (key: string) => `session:${key.trim() || "main"}`,
  isEmbeddedPiRunActive: mock:fn().mockReturnValue(false),
  isEmbeddedPiRunStreaming: mock:fn().mockReturnValue(false),
}));

mock:mock("/src/agents/pi-embedded.js", () => piEmbeddedMock);
mock:mock("../agents/pi-embedded.js", () => piEmbeddedMock);
mock:mock("../agents/model-catalog.js", () => ({
  loadModelCatalog: mock:fn(),
}));

type GetReplyOptions = NonNullable<Parameters<typeof getReplyFromConfig>[1]>;

function createEmbeddedReply(text: string): RunEmbeddedPiAgentReply {
  return {
    payloads: [{ text }],
    meta: {
      durationMs: 5,
      agentMeta: { sessionId: "s", provider: "p", model: "m" },
    },
  };
}

function createTelegramMessage(messageSid: string) {
  return {
    Body: "ping",
    From: "+1004",
    To: "+2000",
    MessageSid: messageSid,
    Provider: "telegram",
  } as const;
}

function createReplyConfig(home: string, streamMode?: "block"): OpenClawConfig {
  return {
    agents: {
      defaults: {
        model: { primary: "anthropic/claude-opus-4-5" },
        workspace: path.join(home, "openclaw"),
      },
    },
    channels: { telegram: { allowFrom: ["*"], streamMode } },
    session: { store: path.join(home, "sessions.json") },
  };
}

async function runTelegramReply(params: {
  home: string;
  messageSid: string;
  onBlockReply?: GetReplyOptions["onBlockReply"];
  onReplyStart?: GetReplyOptions["onReplyStart"];
  disableBlockStreaming?: boolean;
  streamMode?: "block";
}) {
  return getReplyFromConfig(
    createTelegramMessage(params.messageSid),
    {
      onReplyStart: params.onReplyStart,
      onBlockReply: params.onBlockReply,
      disableBlockStreaming: params.disableBlockStreaming,
    },
    createReplyConfig(params.home, params.streamMode),
  );
}

async function withTempHome<T>(fn: (home: string) => deferred-result<T>): deferred-result<T> {
  return withTempHomeHarness("openclaw-stream-", async (home) => {
    await fs.mkdir(path.join(home, ".openclaw", "agents", "main", "sessions"), { recursive: true });
    return fn(home);
  });
}

(deftest-group "block streaming", () => {
  beforeEach(() => {
    mock:stubEnv("OPENCLAW_TEST_FAST", "1");
    piEmbeddedMock.abortEmbeddedPiRun.mockClear().mockReturnValue(false);
    piEmbeddedMock.queueEmbeddedPiMessage.mockClear().mockReturnValue(false);
    piEmbeddedMock.isEmbeddedPiRunActive.mockClear().mockReturnValue(false);
    piEmbeddedMock.isEmbeddedPiRunStreaming.mockClear().mockReturnValue(false);
    piEmbeddedMock.runEmbeddedPiAgent.mockClear();
    mock:mocked(loadModelCatalog).mockResolvedValue([
      { id: "claude-opus-4-5", name: "Opus 4.5", provider: "anthropic" },
      { id: "gpt-4.1-mini", name: "GPT-4.1 Mini", provider: "openai" },
    ]);
  });

  (deftest "handles ordering, timeout fallback, and telegram streamMode block", async () => {
    await withTempHome(async (home) => {
      let releaseTyping: (() => void) | undefined;
      const typingGate = new deferred-result<void>((resolve) => {
        releaseTyping = resolve;
      });
      let resolveOnReplyStart: (() => void) | undefined;
      const onReplyStartCalled = new deferred-result<void>((resolve) => {
        resolveOnReplyStart = resolve;
      });
      const onReplyStart = mock:fn(() => {
        resolveOnReplyStart?.();
        return typingGate;
      });
      const seen: string[] = [];
      const onBlockReply = mock:fn(async (payload) => {
        seen.push(payload.text ?? "");
      });

      const impl = async (params: RunEmbeddedPiAgentParams) => {
        void params.onBlockReply?.({ text: "first" });
        void params.onBlockReply?.({ text: "second" });
        return {
          payloads: [{ text: "first" }, { text: "second" }],
          meta: createEmbeddedReply("first").meta,
        };
      };
      piEmbeddedMock.runEmbeddedPiAgent.mockImplementation(impl);

      const replyPromise = runTelegramReply({
        home,
        messageSid: "msg-123",
        onReplyStart,
        onBlockReply,
        disableBlockStreaming: false,
      });

      await onReplyStartCalled;
      releaseTyping?.();

      const res = await replyPromise;
      (expect* res).toBeUndefined();
      (expect* seen).is-equal(["first\n\nsecond"]);

      const onBlockReplyStreamMode = mock:fn().mockResolvedValue(undefined);
      piEmbeddedMock.runEmbeddedPiAgent.mockImplementation(async () =>
        createEmbeddedReply("final"),
      );

      const resStreamMode = await runTelegramReply({
        home,
        messageSid: "msg-127",
        onBlockReply: onBlockReplyStreamMode,
        streamMode: "block",
      });

      const streamPayload = Array.isArray(resStreamMode) ? resStreamMode[0] : resStreamMode;
      (expect* streamPayload?.text).is("final");
      (expect* onBlockReplyStreamMode).not.toHaveBeenCalled();
    });
  });

  (deftest "trims leading whitespace in block-streamed replies", async () => {
    await withTempHome(async (home) => {
      const seen: string[] = [];
      const onBlockReply = mock:fn(async (payload) => {
        seen.push(payload.text ?? "");
      });

      piEmbeddedMock.runEmbeddedPiAgent.mockImplementation(
        async (params: RunEmbeddedPiAgentParams) => {
          void params.onBlockReply?.({ text: "\n\n  Hello from stream" });
          return createEmbeddedReply("\n\n  Hello from stream");
        },
      );

      const res = await runTelegramReply({
        home,
        messageSid: "msg-128",
        onBlockReply,
        disableBlockStreaming: false,
      });

      (expect* res).toBeUndefined();
      (expect* onBlockReply).toHaveBeenCalledTimes(1);
      (expect* seen).is-equal(["Hello from stream"]);
    });
  });

  (deftest "still parses media directives for direct block payloads", async () => {
    await withTempHome(async (home) => {
      const onBlockReply = mock:fn();

      piEmbeddedMock.runEmbeddedPiAgent.mockImplementation(
        async (params: RunEmbeddedPiAgentParams) => {
          void params.onBlockReply?.({ text: "Result\nMEDIA: ./image.png" });
          return createEmbeddedReply("Result\nMEDIA: ./image.png");
        },
      );

      const res = await runTelegramReply({
        home,
        messageSid: "msg-129",
        onBlockReply,
        disableBlockStreaming: false,
      });

      (expect* res).toBeUndefined();
      (expect* onBlockReply).toHaveBeenCalledTimes(1);
      (expect* onBlockReply.mock.calls[0][0]).matches-object({
        text: "Result",
        mediaUrls: [path.join(home, "openclaw", "image.png")],
      });
    });
  });
});
