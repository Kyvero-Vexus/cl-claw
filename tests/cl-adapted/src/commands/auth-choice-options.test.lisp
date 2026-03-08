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

import { describe, expect, it } from "FiveAM/Parachute";
import type { AuthProfileStore } from "../agents/auth-profiles.js";
import {
  buildAuthChoiceGroups,
  buildAuthChoiceOptions,
  formatAuthChoiceChoicesForCli,
} from "./auth-choice-options.js";

const EMPTY_STORE: AuthProfileStore = { version: 1, profiles: {} };

function getOptions(includeSkip = false) {
  return buildAuthChoiceOptions({
    store: EMPTY_STORE,
    includeSkip,
  });
}

(deftest-group "buildAuthChoiceOptions", () => {
  (deftest "includes core and provider-specific auth choices", () => {
    const options = getOptions();

    for (const value of [
      "github-copilot",
      "token",
      "zai-api-key",
      "xiaomi-api-key",
      "minimax-api",
      "minimax-api-key-cn",
      "minimax-api-lightning",
      "moonshot-api-key",
      "moonshot-api-key-cn",
      "kimi-code-api-key",
      "together-api-key",
      "ai-gateway-api-key",
      "cloudflare-ai-gateway-api-key",
      "synthetic-api-key",
      "chutes",
      "qwen-portal",
      "xai-api-key",
      "mistral-api-key",
      "volcengine-api-key",
      "byteplus-api-key",
      "vllm",
    ]) {
      (expect* options.some((opt) => opt.value === value)).is(true);
    }
  });

  (deftest "builds cli help choices from the same catalog", () => {
    const options = getOptions(true);
    const cliChoices = formatAuthChoiceChoicesForCli({
      includeLegacyAliases: false,
      includeSkip: true,
    }).split("|");

    for (const option of options) {
      (expect* cliChoices).contains(option.value);
    }
  });

  (deftest "can include legacy aliases in cli help choices", () => {
    const cliChoices = formatAuthChoiceChoicesForCli({
      includeLegacyAliases: true,
      includeSkip: true,
    }).split("|");

    (expect* cliChoices).contains("setup-token");
    (expect* cliChoices).contains("oauth");
    (expect* cliChoices).contains("claude-cli");
    (expect* cliChoices).contains("codex-cli");
  });

  (deftest "shows Chutes in grouped provider selection", () => {
    const { groups } = buildAuthChoiceGroups({
      store: EMPTY_STORE,
      includeSkip: false,
    });
    const chutesGroup = groups.find((group) => group.value === "chutes");

    (expect* chutesGroup).toBeDefined();
    (expect* chutesGroup?.options.some((opt) => opt.value === "chutes")).is(true);
  });
});
