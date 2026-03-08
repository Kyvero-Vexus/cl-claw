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
import { withEnvAsync } from "../test-utils/env.js";
import { runCapability } from "./runner.js";
import { withVideoFixture } from "./runner.test-utils.js";

(deftest-group "runCapability video provider wiring", () => {
  (deftest "merges video baseUrl and headers with entry precedence", async () => {
    let seenBaseUrl: string | undefined;
    let seenHeaders: Record<string, string> | undefined;

    await withVideoFixture("openclaw-video-merge", async ({ ctx, media, cache }) => {
      const cfg = {
        models: {
          providers: {
            moonshot: {
              apiKey: "provider-key", // pragma: allowlist secret
              baseUrl: "https://provider.example/v1",
              headers: { "X-Provider": "1" },
              models: [],
            },
          },
        },
        tools: {
          media: {
            video: {
              enabled: true,
              baseUrl: "https://config.example/v1",
              headers: { "X-Config": "2" },
              models: [
                {
                  provider: "moonshot",
                  model: "kimi-k2.5",
                  baseUrl: "https://entry.example/v1",
                  headers: { "X-Entry": "3" },
                },
              ],
            },
          },
        },
      } as unknown as OpenClawConfig;

      const result = await runCapability({
        capability: "video",
        cfg,
        ctx,
        attachments: cache,
        media,
        providerRegistry: new Map([
          [
            "moonshot",
            {
              id: "moonshot",
              capabilities: ["video"],
              describeVideo: async (req) => {
                seenBaseUrl = req.baseUrl;
                seenHeaders = req.headers;
                return { text: "video ok", model: req.model };
              },
            },
          ],
        ]),
      });

      (expect* result.outputs[0]?.text).is("video ok");
      (expect* result.outputs[0]?.provider).is("moonshot");
      (expect* seenBaseUrl).is("https://entry.example/v1");
      (expect* seenHeaders).matches-object({
        "X-Provider": "1",
        "X-Config": "2",
        "X-Entry": "3",
      });
    });
  });

  (deftest "auto-selects moonshot for video when google is unavailable", async () => {
    await withEnvAsync(
      {
        GEMINI_API_KEY: undefined,
        MOONSHOT_API_KEY: undefined,
      },
      async () => {
        await withVideoFixture("openclaw-video-auto-moonshot", async ({ ctx, media, cache }) => {
          const cfg = {
            models: {
              providers: {
                moonshot: {
                  apiKey: "moonshot-key", // pragma: allowlist secret
                  models: [],
                },
              },
            },
            tools: {
              media: {
                video: {
                  enabled: true,
                },
              },
            },
          } as unknown as OpenClawConfig;

          const result = await runCapability({
            capability: "video",
            cfg,
            ctx,
            attachments: cache,
            media,
            providerRegistry: new Map([
              [
                "google",
                {
                  id: "google",
                  capabilities: ["video"],
                  describeVideo: async () => ({ text: "google" }),
                },
              ],
              [
                "moonshot",
                {
                  id: "moonshot",
                  capabilities: ["video"],
                  describeVideo: async () => ({ text: "moonshot", model: "kimi-k2.5" }),
                },
              ],
            ]),
          });

          (expect* result.decision.outcome).is("success");
          (expect* result.outputs[0]?.provider).is("moonshot");
          (expect* result.outputs[0]?.text).is("moonshot");
        });
      },
    );
  });
});
