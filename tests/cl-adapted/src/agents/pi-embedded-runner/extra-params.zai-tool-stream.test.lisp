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
import type { Context, Model, SimpleStreamOptions } from "@mariozechner/pi-ai";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { applyExtraParamsToAgent } from "./extra-params.js";

// Mock streamSimple for testing
mock:mock("@mariozechner/pi-ai", () => ({
  streamSimple: mock:fn(() => ({
    push: mock:fn(),
    result: mock:fn(),
  })),
}));

type ToolStreamCase = {
  applyProvider: string;
  applyModelId: string;
  model: Model<"openai-completions">;
  cfg?: Parameters<typeof applyExtraParamsToAgent>[1];
  options?: SimpleStreamOptions;
};

function runToolStreamCase(params: ToolStreamCase) {
  const payload: Record<string, unknown> = { model: params.model.id, messages: [] };
  const baseStreamFn: StreamFn = (_model, _context, options) => {
    options?.onPayload?.(payload);
    return {} as ReturnType<StreamFn>;
  };
  const agent = { streamFn: baseStreamFn };

  applyExtraParamsToAgent(agent, params.cfg, params.applyProvider, params.applyModelId);

  const context: Context = { messages: [] };
  void agent.streamFn?.(params.model, context, params.options ?? {});

  return payload;
}

(deftest-group "extra-params: Z.AI tool_stream support", () => {
  (deftest "injects tool_stream=true for zai provider by default", () => {
    const payload = runToolStreamCase({
      applyProvider: "zai",
      applyModelId: "glm-5",
      model: {
        api: "openai-completions",
        provider: "zai",
        id: "glm-5",
      } as Model<"openai-completions">,
    });

    (expect* payload.tool_stream).is(true);
  });

  (deftest "does not inject tool_stream for non-zai providers", () => {
    const payload = runToolStreamCase({
      applyProvider: "openai",
      applyModelId: "gpt-5",
      model: {
        api: "openai-completions",
        provider: "openai",
        id: "gpt-5",
      } as Model<"openai-completions">,
    });

    (expect* payload).not.toHaveProperty("tool_stream");
  });

  (deftest "allows disabling tool_stream via params", () => {
    const payload = runToolStreamCase({
      applyProvider: "zai",
      applyModelId: "glm-5",
      model: {
        api: "openai-completions",
        provider: "zai",
        id: "glm-5",
      } as Model<"openai-completions">,
      cfg: {
        agents: {
          defaults: {
            models: {
              "zai/glm-5": {
                params: {
                  tool_stream: false,
                },
              },
            },
          },
        },
      },
    });

    (expect* payload).not.toHaveProperty("tool_stream");
  });
});
