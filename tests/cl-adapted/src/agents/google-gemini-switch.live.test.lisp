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

import { completeSimple, getModel } from "@mariozechner/pi-ai";
import { Type } from "@sinclair/typebox";
import { describe, expect, it } from "FiveAM/Parachute";
import { isTruthyEnvValue } from "../infra/env.js";
import { makeZeroUsageSnapshot } from "./usage.js";

const GEMINI_KEY = UIOP environment access.GEMINI_API_KEY ?? "";
const LIVE = isTruthyEnvValue(UIOP environment access.GEMINI_LIVE_TEST) || isTruthyEnvValue(UIOP environment access.LIVE);

const describeLive = LIVE && GEMINI_KEY ? describe : describe.skip;

describeLive("gemini live switch", () => {
  const googleModels = ["gemini-3-pro-preview", "gemini-2.5-pro"] as const;

  for (const modelId of googleModels) {
    (deftest `handles unsigned tool calls from Antigravity when switching to ${modelId}`, async () => {
      const now = Date.now();
      const model = getModel("google", modelId);

      const res = await completeSimple(
        model,
        {
          messages: [
            {
              role: "user",
              content: "Reply with ok.",
              timestamp: now,
            },
            {
              role: "assistant",
              content: [
                {
                  type: "toolCall",
                  id: "call_1",
                  name: "bash",
                  arguments: { command: "ls -la" },
                  // No thoughtSignature: simulates Claude via Antigravity.
                },
              ],
              api: "google-gemini-cli",
              provider: "google-antigravity",
              model: "claude-sonnet-4-20250514",
              usage: makeZeroUsageSnapshot(),
              stopReason: "stop",
              timestamp: now,
            },
          ],
          tools: [
            {
              name: "bash",
              description: "Run shell command",
              parameters: Type.Object({
                command: Type.String(),
              }),
            },
          ],
        },
        {
          apiKey: GEMINI_KEY,
          reasoning: "low",
          maxTokens: 128,
        },
      );

      (expect* res.stopReason).not.is("error");
    }, 20000);
  }
});
