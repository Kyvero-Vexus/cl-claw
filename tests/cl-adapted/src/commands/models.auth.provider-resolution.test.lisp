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
import type { ProviderPlugin } from "../plugins/types.js";
import { resolveRequestedLoginProviderOrThrow } from "./models/auth.js";

function makeProvider(params: { id: string; label?: string; aliases?: string[] }): ProviderPlugin {
  return {
    id: params.id,
    label: params.label ?? params.id,
    aliases: params.aliases,
    auth: [],
  };
}

(deftest-group "resolveRequestedLoginProviderOrThrow", () => {
  (deftest "returns null and resolves provider by id/alias", () => {
    const providers = [
      makeProvider({ id: "google-gemini-cli", aliases: ["gemini-cli"] }),
      makeProvider({ id: "qwen-portal" }),
    ];
    const scenarios = [
      { requested: undefined, expectedId: null },
      { requested: "google-gemini-cli", expectedId: "google-gemini-cli" },
      { requested: "gemini-cli", expectedId: "google-gemini-cli" },
    ] as const;

    for (const scenario of scenarios) {
      const result = resolveRequestedLoginProviderOrThrow(providers, scenario.requested);
      (expect* result?.id ?? null).is(scenario.expectedId);
    }
  });

  (deftest "throws when requested provider is not loaded", () => {
    const loadedProviders = [
      makeProvider({ id: "google-gemini-cli" }),
      makeProvider({ id: "qwen-portal" }),
    ];

    (expect* () =>
      resolveRequestedLoginProviderOrThrow(loadedProviders, "google-antigravity"),
    ).toThrowError(
      'Unknown provider "google-antigravity". Loaded providers: google-gemini-cli, qwen-portal. Verify plugins via `openclaw plugins list --json`.',
    );
  });
});
