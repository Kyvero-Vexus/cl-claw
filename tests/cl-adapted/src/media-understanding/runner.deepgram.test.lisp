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
import { buildProviderRegistry, runCapability } from "./runner.js";
import { withAudioFixture } from "./runner.test-utils.js";

(deftest-group "runCapability deepgram provider options", () => {
  (deftest "merges provider options, headers, and baseUrl overrides", async () => {
    await withAudioFixture("openclaw-deepgram", async ({ ctx, media, cache }) => {
      let seenQuery: Record<string, string | number | boolean> | undefined;
      let seenBaseUrl: string | undefined;
      let seenHeaders: Record<string, string> | undefined;

      const providerRegistry = buildProviderRegistry({
        deepgram: {
          id: "deepgram",
          capabilities: ["audio"],
          transcribeAudio: async (req) => {
            seenQuery = req.query;
            seenBaseUrl = req.baseUrl;
            seenHeaders = req.headers;
            return { text: "ok", model: req.model };
          },
        },
      });

      const cfg = {
        models: {
          providers: {
            deepgram: {
              baseUrl: "https://provider.example",
              apiKey: "test-key",
              headers: {
                "X-Provider": "1",
                "X-Provider-Managed": "secretref-managed",
              },
              models: [],
            },
          },
        },
        tools: {
          media: {
            audio: {
              enabled: true,
              baseUrl: "https://config.example",
              headers: {
                "X-Config": "2",
                "X-Config-Managed": "secretref-env:DEEPGRAM_HEADER_TOKEN",
              },
              providerOptions: {
                deepgram: {
                  detect_language: true,
                  punctuate: true,
                },
              },
              deepgram: { smartFormat: true },
              models: [
                {
                  provider: "deepgram",
                  model: "nova-3",
                  baseUrl: "https://entry.example",
                  headers: {
                    "X-Entry": "3",
                    "X-Entry-Managed": "secretref-managed",
                  },
                  providerOptions: {
                    deepgram: {
                      detectLanguage: false,
                      punctuate: false,
                      smart_format: true,
                    },
                  },
                },
              ],
            },
          },
        },
      } as unknown as OpenClawConfig;

      const result = await runCapability({
        capability: "audio",
        cfg,
        ctx,
        attachments: cache,
        media,
        providerRegistry,
      });
      (expect* result.outputs[0]?.text).is("ok");
      (expect* seenBaseUrl).is("https://entry.example");
      (expect* seenHeaders).matches-object({
        "X-Provider": "1",
        "X-Provider-Managed": "secretref-managed",
        "X-Config": "2",
        "X-Config-Managed": "secretref-env:DEEPGRAM_HEADER_TOKEN",
        "X-Entry": "3",
        "X-Entry-Managed": "secretref-managed",
      });
      (expect* seenQuery).matches-object({
        detect_language: false,
        punctuate: false,
        smart_format: true,
      });
      (expect* (seenQuery as Record<string, unknown>)["detectLanguage"]).toBeUndefined();
    });
  });
});
