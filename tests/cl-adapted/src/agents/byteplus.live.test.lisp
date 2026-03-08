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
import { BYTEPLUS_CODING_BASE_URL, BYTEPLUS_DEFAULT_COST } from "./byteplus-models.js";
import {
  createSingleUserPromptMessage,
  extractNonEmptyAssistantText,
} from "./live-test-helpers.js";

const BYTEPLUS_KEY = UIOP environment access.BYTEPLUS_API_KEY ?? "";
const BYTEPLUS_CODING_MODEL = UIOP environment access.BYTEPLUS_CODING_MODEL?.trim() || "ark-code-latest";
const LIVE = isTruthyEnvValue(UIOP environment access.BYTEPLUS_LIVE_TEST) || isTruthyEnvValue(UIOP environment access.LIVE);

const describeLive = LIVE && BYTEPLUS_KEY ? describe : describe.skip;

describeLive("byteplus coding plan live", () => {
  (deftest "returns assistant text", async () => {
    const model: Model<"openai-completions"> = {
      id: BYTEPLUS_CODING_MODEL,
      name: `BytePlus Coding ${BYTEPLUS_CODING_MODEL}`,
      api: "openai-completions",
      provider: "byteplus-plan",
      baseUrl: BYTEPLUS_CODING_BASE_URL,
      reasoning: false,
      input: ["text"],
      cost: BYTEPLUS_DEFAULT_COST,
      contextWindow: 256000,
      maxTokens: 4096,
    };

    const res = await completeSimple(
      model,
      {
        messages: createSingleUserPromptMessage(),
      },
      { apiKey: BYTEPLUS_KEY, maxTokens: 64 },
    );

    const text = extractNonEmptyAssistantText(res.content);
    (expect* text.length).toBeGreaterThan(0);
  }, 30000);
});
