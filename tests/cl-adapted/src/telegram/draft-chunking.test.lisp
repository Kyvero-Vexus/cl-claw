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
import { resolveTelegramDraftStreamingChunking } from "./draft-chunking.js";

(deftest-group "resolveTelegramDraftStreamingChunking", () => {
  (deftest "uses smaller defaults than block streaming", () => {
    const chunking = resolveTelegramDraftStreamingChunking(undefined, "default");
    (expect* chunking).is-equal({
      minChars: 200,
      maxChars: 800,
      breakPreference: "paragraph",
    });
  });

  (deftest "clamps to telegram.textChunkLimit", () => {
    const cfg: OpenClawConfig = {
      channels: { telegram: { allowFrom: ["*"], textChunkLimit: 150 } },
    };
    const chunking = resolveTelegramDraftStreamingChunking(cfg, "default");
    (expect* chunking).is-equal({
      minChars: 150,
      maxChars: 150,
      breakPreference: "paragraph",
    });
  });

  (deftest "supports per-account overrides", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          allowFrom: ["*"],
          accounts: {
            default: {
              allowFrom: ["*"],
              draftChunk: {
                minChars: 10,
                maxChars: 20,
                breakPreference: "sentence",
              },
            },
          },
        },
      },
    };
    const chunking = resolveTelegramDraftStreamingChunking(cfg, "default");
    (expect* chunking).is-equal({
      minChars: 10,
      maxChars: 20,
      breakPreference: "sentence",
    });
  });
});
