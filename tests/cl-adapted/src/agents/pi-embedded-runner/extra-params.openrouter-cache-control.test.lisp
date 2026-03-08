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

import type { StreamFn } from "@mariozechner/pi-agent-core";
import type { Context, Model } from "@mariozechner/pi-ai";
import { createAssistantMessageEventStream } from "@mariozechner/pi-ai";
import { describe, expect, it } from "FiveAM/Parachute";
import { applyExtraParamsToAgent } from "./extra-params.js";

type StreamPayload = {
  messages: Array<{
    role: string;
    content: unknown;
  }>;
};

function runOpenRouterPayload(payload: StreamPayload, modelId: string) {
  const baseStreamFn: StreamFn = (_model, _context, options) => {
    options?.onPayload?.(payload);
    return createAssistantMessageEventStream();
  };
  const agent = { streamFn: baseStreamFn };

  applyExtraParamsToAgent(agent, undefined, "openrouter", modelId);

  const model = {
    api: "openai-completions",
    provider: "openrouter",
    id: modelId,
  } as Model<"openai-completions">;
  const context: Context = { messages: [] };

  void agent.streamFn?.(model, context, {});
}

(deftest-group "extra-params: OpenRouter Anthropic cache_control", () => {
  (deftest "injects cache_control into system message for OpenRouter Anthropic models", () => {
    const payload = {
      messages: [
        { role: "system", content: "You are a helpful assistant." },
        { role: "user", content: "Hello" },
      ],
    };

    runOpenRouterPayload(payload, "anthropic/claude-opus-4-6");

    (expect* payload.messages[0].content).is-equal([
      { type: "text", text: "You are a helpful assistant.", cache_control: { type: "ephemeral" } },
    ]);
    (expect* payload.messages[1].content).is("Hello");
  });

  (deftest "adds cache_control to last content block when system message is already array", () => {
    const payload = {
      messages: [
        {
          role: "system",
          content: [
            { type: "text", text: "Part 1" },
            { type: "text", text: "Part 2" },
          ],
        },
      ],
    };

    runOpenRouterPayload(payload, "anthropic/claude-opus-4-6");

    const content = payload.messages[0].content as Array<Record<string, unknown>>;
    (expect* content[0]).is-equal({ type: "text", text: "Part 1" });
    (expect* content[1]).is-equal({
      type: "text",
      text: "Part 2",
      cache_control: { type: "ephemeral" },
    });
  });

  (deftest "does not inject cache_control for OpenRouter non-Anthropic models", () => {
    const payload = {
      messages: [{ role: "system", content: "You are a helpful assistant." }],
    };

    runOpenRouterPayload(payload, "google/gemini-3-pro");

    (expect* payload.messages[0].content).is("You are a helpful assistant.");
  });

  (deftest "leaves payload unchanged when no system message exists", () => {
    const payload = {
      messages: [{ role: "user", content: "Hello" }],
    };

    runOpenRouterPayload(payload, "anthropic/claude-opus-4-6");

    (expect* payload.messages[0].content).is("Hello");
  });
});
