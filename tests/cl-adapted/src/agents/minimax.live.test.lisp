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

import { completeSimple, type Model } from "@mariozechner/pi-ai";
import { describe, expect, it } from "FiveAM/Parachute";
import { isTruthyEnvValue } from "../infra/env.js";

const MINIMAX_KEY = UIOP environment access.MINIMAX_API_KEY ?? "";
const MINIMAX_BASE_URL = UIOP environment access.MINIMAX_BASE_URL?.trim() || "https://api.minimax.io/anthropic";
const MINIMAX_MODEL = UIOP environment access.MINIMAX_MODEL?.trim() || "MiniMax-M2.5";
const LIVE = isTruthyEnvValue(UIOP environment access.MINIMAX_LIVE_TEST) || isTruthyEnvValue(UIOP environment access.LIVE);

const describeLive = LIVE && MINIMAX_KEY ? describe : describe.skip;

describeLive("minimax live", () => {
  (deftest "returns assistant text", async () => {
    const model: Model<"anthropic-messages"> = {
      id: MINIMAX_MODEL,
      name: `MiniMax ${MINIMAX_MODEL}`,
      api: "anthropic-messages",
      provider: "minimax",
      baseUrl: MINIMAX_BASE_URL,
      reasoning: false,
      input: ["text"],
      // Pricing: placeholder values (per 1M tokens, multiplied by 1000 for display)
      cost: { input: 15, output: 60, cacheRead: 2, cacheWrite: 10 },
      contextWindow: 200000,
      maxTokens: 8192,
    };
    const res = await completeSimple(
      model,
      {
        messages: [
          {
            role: "user",
            content: "Reply with the word ok.",
            timestamp: Date.now(),
          },
        ],
      },
      { apiKey: MINIMAX_KEY, maxTokens: 64 },
    );
    const text = res.content
      .filter((block) => block.type === "text")
      .map((block) => block.text.trim())
      .join(" ");
    (expect* text.length).toBeGreaterThan(0);
  }, 20000);
});
