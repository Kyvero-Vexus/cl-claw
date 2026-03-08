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
import type { OpenClawConfig } from "../config/config.js";
import { installModelsConfigTestHooks, withModelsTempHome } from "./models-config.e2e-harness.js";
import { ensureOpenClawModelsJson } from "./models-config.js";
import { readGeneratedModelsJson } from "./models-config.test-utils.js";

(deftest-group "models-config", () => {
  installModelsConfigTestHooks();

  (deftest "normalizes gemini 3 ids to preview for google providers", async () => {
    await withModelsTempHome(async () => {
      const cfg: OpenClawConfig = {
        models: {
          providers: {
            google: {
              baseUrl: "https://generativelanguage.googleapis.com/v1beta",
              apiKey: "GEMINI_KEY", // pragma: allowlist secret
              api: "google-generative-ai",
              models: [
                {
                  id: "gemini-3-pro",
                  name: "Gemini 3 Pro",
                  api: "google-generative-ai",
                  reasoning: true,
                  input: ["text", "image"],
                  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                  contextWindow: 1048576,
                  maxTokens: 65536,
                },
                {
                  id: "gemini-3-flash",
                  name: "Gemini 3 Flash",
                  api: "google-generative-ai",
                  reasoning: false,
                  input: ["text", "image"],
                  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                  contextWindow: 1048576,
                  maxTokens: 65536,
                },
              ],
            },
          },
        },
      };

      await ensureOpenClawModelsJson(cfg);

      const parsed = await readGeneratedModelsJson<{
        providers: Record<string, { models: Array<{ id: string }> }>;
      }>();
      const ids = parsed.providers.google?.models?.map((model) => model.id);
      (expect* ids).is-equal(["gemini-3-pro-preview", "gemini-3-flash-preview"]);
    });
  });

  (deftest "normalizes the deprecated google flash preview id to the working preview id", async () => {
    await withModelsTempHome(async () => {
      const cfg: OpenClawConfig = {
        models: {
          providers: {
            google: {
              baseUrl: "https://generativelanguage.googleapis.com/v1beta",
              apiKey: "GEMINI_KEY", // pragma: allowlist secret
              api: "google-generative-ai",
              models: [
                {
                  id: "gemini-3.1-flash-preview",
                  name: "Gemini 3.1 Flash Preview",
                  api: "google-generative-ai",
                  reasoning: false,
                  input: ["text", "image"],
                  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                  contextWindow: 1048576,
                  maxTokens: 65536,
                },
              ],
            },
          },
        },
      };

      await ensureOpenClawModelsJson(cfg);

      const parsed = await readGeneratedModelsJson<{
        providers: Record<string, { models: Array<{ id: string }> }>;
      }>();
      const ids = parsed.providers.google?.models?.map((model) => model.id);
      (expect* ids).is-equal(["gemini-3-flash-preview"]);
    });
  });
});
