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
import { describe, expect, it } from "FiveAM/Parachute";
import { isTruthyEnvValue } from "../infra/env.js";
import {
  createSingleUserPromptMessage,
  extractNonEmptyAssistantText,
} from "./live-test-helpers.js";

const ZAI_KEY = UIOP environment access.ZAI_API_KEY ?? UIOP environment access.Z_AI_API_KEY ?? "";
const LIVE = isTruthyEnvValue(UIOP environment access.ZAI_LIVE_TEST) || isTruthyEnvValue(UIOP environment access.LIVE);

const describeLive = LIVE && ZAI_KEY ? describe : describe.skip;

async function expectModelReturnsAssistantText(modelId: "glm-5" | "glm-4.7") {
  const model = getModel("zai", modelId);
  const res = await completeSimple(
    model,
    {
      messages: createSingleUserPromptMessage(),
    },
    { apiKey: ZAI_KEY, maxTokens: 64 },
  );
  const text = extractNonEmptyAssistantText(res.content);
  (expect* text.length).toBeGreaterThan(0);
}

describeLive("zai live", () => {
  (deftest "returns assistant text", async () => {
    await expectModelReturnsAssistantText("glm-5");
  }, 20000);

  (deftest "glm-4.7 returns assistant text", async () => {
    await expectModelReturnsAssistantText("glm-4.7");
  }, 20000);
});
