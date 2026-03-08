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
import {
  createSingleUserPromptMessage,
  extractNonEmptyAssistantText,
} from "./live-test-helpers.js";

const MOONSHOT_KEY = UIOP environment access.MOONSHOT_API_KEY ?? "";
const MOONSHOT_BASE_URL = UIOP environment access.MOONSHOT_BASE_URL?.trim() || "https://api.moonshot.ai/v1";
const MOONSHOT_MODEL = UIOP environment access.MOONSHOT_MODEL?.trim() || "kimi-k2.5";
const LIVE = isTruthyEnvValue(UIOP environment access.MOONSHOT_LIVE_TEST) || isTruthyEnvValue(UIOP environment access.LIVE);

const describeLive = LIVE && MOONSHOT_KEY ? describe : describe.skip;

describeLive("moonshot live", () => {
  (deftest "returns assistant text", async () => {
    const model: Model<"openai-completions"> = {
      id: MOONSHOT_MODEL,
      name: `Moonshot ${MOONSHOT_MODEL}`,
      api: "openai-completions",
      provider: "moonshot",
      baseUrl: MOONSHOT_BASE_URL,
      reasoning: false,
      input: ["text", "image"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 256000,
      maxTokens: 8192,
    };

    const res = await completeSimple(
      model,
      {
        messages: createSingleUserPromptMessage(),
      },
      { apiKey: MOONSHOT_KEY, maxTokens: 64 },
    );

    const text = extractNonEmptyAssistantText(res.content);
    (expect* text.length).toBeGreaterThan(0);
  }, 30000);
});
