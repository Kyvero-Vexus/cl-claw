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
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { TemplateContext } from "../templating.js";
import type { FollowupRun, QueueSettings } from "./queue.js";
import { createMockTypingController } from "./test-helpers.js";

const runEmbeddedPiAgentMock = mock:fn();
const runWithModelFallbackMock = mock:fn();

mock:mock("../../agents/model-fallback.js", () => ({
  runWithModelFallback: (params: {
    provider: string;
    model: string;
    run: (provider: string, model: string) => deferred-result<unknown>;
  }) => runWithModelFallbackMock(params),
}));

mock:mock("../../agents/pi-embedded.js", async () => {
  const actual = await mock:importActual<typeof import("../../agents/pi-embedded.js")>(
    "../../agents/pi-embedded.js",
  );
  return {
    ...actual,
    queueEmbeddedPiMessage: mock:fn().mockReturnValue(false),
    runEmbeddedPiAgent: (params: unknown) => runEmbeddedPiAgentMock(params),
  };
});

mock:mock("./queue.js", async () => {
  const actual = await mock:importActual<typeof import("./queue.js")>("./queue.js");
  return {
    ...actual,
    enqueueFollowupRun: mock:fn(),
    scheduleFollowupDrain: mock:fn(),
  };
});

import { runReplyAgent } from "./agent-runner.js";

(deftest-group "runReplyAgent media path normalization", () => {
  beforeEach(() => {
    runEmbeddedPiAgentMock.mockReset();
    runWithModelFallbackMock.mockReset();
    runWithModelFallbackMock.mockImplementation(
      async ({
        provider,
        model,
        run,
      }: {
        provider: string;
        model: string;
        run: (...args: unknown[]) => deferred-result<unknown>;
      }) => ({
        result: await run(provider, model),
        provider,
        model,
      }),
    );
  });

  (deftest "normalizes final MEDIA replies against the run workspace", async () => {
    runEmbeddedPiAgentMock.mockResolvedValue({
      payloads: [{ text: "MEDIA:./out/generated.png" }],
      meta: {
        agentMeta: {
          sessionId: "session",
          provider: "anthropic",
          model: "claude",
        },
      },
    });

    const result = await runReplyAgent({
      commandBody: "generate",
      followupRun: {
        prompt: "generate",
        enqueuedAt: Date.now(),
        run: {
          agentId: "main",
          agentDir: "/tmp/agent",
          sessionId: "session",
          sessionKey: "main",
          messageProvider: "telegram",
          sessionFile: "/tmp/session.jsonl",
          workspaceDir: "/tmp/workspace",
          config: {},
          provider: "anthropic",
          model: "claude",
          thinkLevel: "low",
          verboseLevel: "off",
          elevatedLevel: "off",
          bashElevated: {
            enabled: false,
            allowed: false,
            defaultLevel: "off",
          },
          timeoutMs: 1_000,
          blockReplyBreak: "message_end",
        },
      } as unknown as FollowupRun,
      queueKey: "main",
      resolvedQueue: { mode: "interrupt" } as QueueSettings,
      shouldSteer: false,
      shouldFollowup: false,
      isActive: false,
      isStreaming: false,
      typing: createMockTypingController(),
      sessionCtx: {
        Provider: "telegram",
        Surface: "telegram",
        To: "chat-1",
        OriginatingTo: "chat-1",
        AccountId: "default",
        MessageSid: "msg-1",
      } as unknown as TemplateContext,
      defaultModel: "anthropic/claude",
      resolvedVerboseLevel: "off",
      isNewSession: false,
      blockStreamingEnabled: false,
      resolvedBlockStreamingBreak: "message_end",
      shouldInjectGroupIntro: false,
      typingMode: "instant",
    });

    (expect* result).matches-object({
      mediaUrl: path.join("/tmp/workspace", "out", "generated.png"),
      mediaUrls: [path.join("/tmp/workspace", "out", "generated.png")],
    });
  });
});
