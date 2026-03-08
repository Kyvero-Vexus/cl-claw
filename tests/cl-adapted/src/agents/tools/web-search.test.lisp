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
import { withEnv } from "../../test-utils/env.js";
import { __testing } from "./web-search.js";

const {
  normalizeBraveLanguageParams,
  normalizeFreshness,
  normalizeToIsoDate,
  isoToPerplexityDate,
  resolveGrokApiKey,
  resolveGrokModel,
  resolveGrokInlineCitations,
  extractGrokContent,
  resolveKimiApiKey,
  resolveKimiModel,
  resolveKimiBaseUrl,
  extractKimiCitations,
} = __testing;

const kimiApiKeyEnv = ["KIMI_API", "KEY"].join("_");
const moonshotApiKeyEnv = ["MOONSHOT_API", "KEY"].join("_");

(deftest-group "web_search brave language param normalization", () => {
  (deftest "normalizes and auto-corrects swapped Brave language params", () => {
    (expect* normalizeBraveLanguageParams({ search_lang: "tr-TR", ui_lang: "tr" })).is-equal({
      search_lang: "tr",
      ui_lang: "tr-TR",
    });
    (expect* normalizeBraveLanguageParams({ search_lang: "EN", ui_lang: "en-us" })).is-equal({
      search_lang: "en",
      ui_lang: "en-US",
    });
  });

  (deftest "flags invalid Brave language formats", () => {
    (expect* normalizeBraveLanguageParams({ search_lang: "en-US" })).is-equal({
      invalidField: "search_lang",
    });
    (expect* normalizeBraveLanguageParams({ ui_lang: "en" })).is-equal({
      invalidField: "ui_lang",
    });
  });
});

(deftest-group "web_search freshness normalization", () => {
  (deftest "accepts Brave shortcut values and maps for Perplexity", () => {
    (expect* normalizeFreshness("pd", "brave")).is("pd");
    (expect* normalizeFreshness("PW", "brave")).is("pw");
    (expect* normalizeFreshness("pd", "perplexity")).is("day");
    (expect* normalizeFreshness("pw", "perplexity")).is("week");
  });

  (deftest "accepts Perplexity values and maps for Brave", () => {
    (expect* normalizeFreshness("day", "perplexity")).is("day");
    (expect* normalizeFreshness("week", "perplexity")).is("week");
    (expect* normalizeFreshness("day", "brave")).is("pd");
    (expect* normalizeFreshness("week", "brave")).is("pw");
  });

  (deftest "accepts valid date ranges for Brave", () => {
    (expect* normalizeFreshness("2024-01-01to2024-01-31", "brave")).is("2024-01-01to2024-01-31");
  });

  (deftest "rejects invalid values", () => {
    (expect* normalizeFreshness("yesterday", "brave")).toBeUndefined();
    (expect* normalizeFreshness("yesterday", "perplexity")).toBeUndefined();
    (expect* normalizeFreshness("2024-01-01to2024-01-31", "perplexity")).toBeUndefined();
  });

  (deftest "rejects invalid date ranges for Brave", () => {
    (expect* normalizeFreshness("2024-13-01to2024-01-31", "brave")).toBeUndefined();
    (expect* normalizeFreshness("2024-02-30to2024-03-01", "brave")).toBeUndefined();
    (expect* normalizeFreshness("2024-03-10to2024-03-01", "brave")).toBeUndefined();
  });
});

(deftest-group "web_search date normalization", () => {
  (deftest "accepts ISO format", () => {
    (expect* normalizeToIsoDate("2024-01-15")).is("2024-01-15");
    (expect* normalizeToIsoDate("2025-12-31")).is("2025-12-31");
  });

  (deftest "accepts Perplexity format and converts to ISO", () => {
    (expect* normalizeToIsoDate("1/15/2024")).is("2024-01-15");
    (expect* normalizeToIsoDate("12/31/2025")).is("2025-12-31");
  });

  (deftest "rejects invalid formats", () => {
    (expect* normalizeToIsoDate("01-15-2024")).toBeUndefined();
    (expect* normalizeToIsoDate("2024/01/15")).toBeUndefined();
    (expect* normalizeToIsoDate("invalid")).toBeUndefined();
  });

  (deftest "converts ISO to Perplexity format", () => {
    (expect* isoToPerplexityDate("2024-01-15")).is("1/15/2024");
    (expect* isoToPerplexityDate("2025-12-31")).is("12/31/2025");
    (expect* isoToPerplexityDate("2024-03-05")).is("3/5/2024");
  });

  (deftest "rejects invalid ISO dates", () => {
    (expect* isoToPerplexityDate("1/15/2024")).toBeUndefined();
    (expect* isoToPerplexityDate("invalid")).toBeUndefined();
  });
});

(deftest-group "web_search grok config resolution", () => {
  (deftest "uses config apiKey when provided", () => {
    (expect* resolveGrokApiKey({ apiKey: "xai-test-key" })).is("xai-test-key"); // pragma: allowlist secret
  });

  (deftest "returns undefined when no apiKey is available", () => {
    withEnv({ XAI_API_KEY: undefined }, () => {
      (expect* resolveGrokApiKey({})).toBeUndefined();
      (expect* resolveGrokApiKey(undefined)).toBeUndefined();
    });
  });

  (deftest "uses default model when not specified", () => {
    (expect* resolveGrokModel({})).is("grok-4-1-fast");
    (expect* resolveGrokModel(undefined)).is("grok-4-1-fast");
  });

  (deftest "uses config model when provided", () => {
    (expect* resolveGrokModel({ model: "grok-3" })).is("grok-3");
  });

  (deftest "defaults inlineCitations to false", () => {
    (expect* resolveGrokInlineCitations({})).is(false);
    (expect* resolveGrokInlineCitations(undefined)).is(false);
  });

  (deftest "respects inlineCitations config", () => {
    (expect* resolveGrokInlineCitations({ inlineCitations: true })).is(true);
    (expect* resolveGrokInlineCitations({ inlineCitations: false })).is(false);
  });
});

(deftest-group "web_search grok response parsing", () => {
  (deftest "extracts content from Responses API message blocks", () => {
    const result = extractGrokContent({
      output: [
        {
          type: "message",
          content: [{ type: "output_text", text: "hello from output" }],
        },
      ],
    });
    (expect* result.text).is("hello from output");
    (expect* result.annotationCitations).is-equal([]);
  });

  (deftest "extracts url_citation annotations from content blocks", () => {
    const result = extractGrokContent({
      output: [
        {
          type: "message",
          content: [
            {
              type: "output_text",
              text: "hello with citations",
              annotations: [
                {
                  type: "url_citation",
                  url: "https://example.com/a",
                  start_index: 0,
                  end_index: 5,
                },
                {
                  type: "url_citation",
                  url: "https://example.com/b",
                  start_index: 6,
                  end_index: 10,
                },
                {
                  type: "url_citation",
                  url: "https://example.com/a",
                  start_index: 11,
                  end_index: 15,
                }, // duplicate
              ],
            },
          ],
        },
      ],
    });
    (expect* result.text).is("hello with citations");
    (expect* result.annotationCitations).is-equal(["https://example.com/a", "https://example.com/b"]);
  });

  (deftest "falls back to deprecated output_text", () => {
    const result = extractGrokContent({ output_text: "hello from output_text" });
    (expect* result.text).is("hello from output_text");
    (expect* result.annotationCitations).is-equal([]);
  });

  (deftest "returns undefined text when no content found", () => {
    const result = extractGrokContent({});
    (expect* result.text).toBeUndefined();
    (expect* result.annotationCitations).is-equal([]);
  });

  (deftest "extracts output_text blocks directly in output array (no message wrapper)", () => {
    const result = extractGrokContent({
      output: [
        { type: "web_search_call" },
        {
          type: "output_text",
          text: "direct output text",
          annotations: [
            {
              type: "url_citation",
              url: "https://example.com/direct",
              start_index: 0,
              end_index: 5,
            },
          ],
        },
      ],
    } as Parameters<typeof extractGrokContent>[0]);
    (expect* result.text).is("direct output text");
    (expect* result.annotationCitations).is-equal(["https://example.com/direct"]);
  });
});

(deftest-group "web_search kimi config resolution", () => {
  (deftest "uses config apiKey when provided", () => {
    (expect* resolveKimiApiKey({ apiKey: "kimi-test-key" })).is("kimi-test-key"); // pragma: allowlist secret
  });

  (deftest "falls back to KIMI_API_KEY, then MOONSHOT_API_KEY", () => {
    const kimiEnvValue = "kimi-env"; // pragma: allowlist secret
    const moonshotEnvValue = "moonshot-env"; // pragma: allowlist secret
    withEnv({ [kimiApiKeyEnv]: kimiEnvValue, [moonshotApiKeyEnv]: moonshotEnvValue }, () => {
      (expect* resolveKimiApiKey({})).is(kimiEnvValue);
    });
    withEnv({ [kimiApiKeyEnv]: undefined, [moonshotApiKeyEnv]: moonshotEnvValue }, () => {
      (expect* resolveKimiApiKey({})).is(moonshotEnvValue);
    });
  });

  (deftest "returns undefined when no Kimi key is configured", () => {
    withEnv({ KIMI_API_KEY: undefined, MOONSHOT_API_KEY: undefined }, () => {
      (expect* resolveKimiApiKey({})).toBeUndefined();
      (expect* resolveKimiApiKey(undefined)).toBeUndefined();
    });
  });

  (deftest "resolves default model and baseUrl", () => {
    (expect* resolveKimiModel({})).is("moonshot-v1-128k");
    (expect* resolveKimiBaseUrl({})).is("https://api.moonshot.ai/v1");
  });
});

(deftest-group "extractKimiCitations", () => {
  (deftest "collects unique URLs from search_results and tool arguments", () => {
    (expect* 
      extractKimiCitations({
        search_results: [{ url: "https://example.com/a" }, { url: "https://example.com/a" }],
        choices: [
          {
            message: {
              tool_calls: [
                {
                  function: {
                    arguments: JSON.stringify({
                      search_results: [{ url: "https://example.com/b" }],
                      url: "https://example.com/c",
                    }),
                  },
                },
              ],
            },
          },
        ],
      }).toSorted(),
    ).is-equal(["https://example.com/a", "https://example.com/b", "https://example.com/c"]);
  });
});
