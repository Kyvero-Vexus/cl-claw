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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { AuthProfileStore } from "../../agents/auth-profiles.js";
import type { OpenClawConfig } from "../../config/config.js";

let mockStore: AuthProfileStore;
let mockOrder: string[];

mock:mock("../../agents/auth-health.js", () => ({
  formatRemainingShort: () => "1h",
}));

mock:mock("../../agents/auth-profiles.js", () => ({
  isProfileInCooldown: () => false,
  resolveAuthProfileDisplayLabel: ({ profileId }: { profileId: string }) => profileId,
  resolveAuthStorePathForDisplay: () => "/tmp/auth-profiles.json",
}));

mock:mock("../../agents/model-selection.js", () => ({
  findNormalizedProviderValue: (
    values: Record<string, unknown> | undefined,
    provider: string,
  ): unknown => {
    if (!values) {
      return undefined;
    }
    return Object.entries(values).find(
      ([key]) => key.toLowerCase() === provider.toLowerCase(),
    )?.[1];
  },
  normalizeProviderId: (provider: string) => provider.trim().toLowerCase(),
}));

mock:mock("../../agents/model-auth.js", () => ({
  ensureAuthProfileStore: () => mockStore,
  getCustomProviderApiKey: () => undefined,
  resolveAuthProfileOrder: () => mockOrder,
  resolveEnvApiKey: () => null,
}));

const { resolveAuthLabel } = await import("./directive-handling.auth.js");

(deftest-group "resolveAuthLabel ref-aware labels", () => {
  beforeEach(() => {
    mockStore = {
      version: 1,
      profiles: {},
    };
    mockOrder = [];
  });

  (deftest "shows api-key (ref) for keyRef-only profiles in compact mode", async () => {
    mockStore.profiles = {
      "openai:default": {
        type: "api_key",
        provider: "openai",
        keyRef: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
      },
    };
    mockOrder = ["openai:default"];

    const result = await resolveAuthLabel(
      "openai",
      {} as OpenClawConfig,
      "/tmp/models.json",
      undefined,
      "compact",
    );

    (expect* result.label).is("openai:default api-key (ref)");
  });

  (deftest "shows token (ref) for tokenRef-only profiles in compact mode", async () => {
    mockStore.profiles = {
      "github-copilot:default": {
        type: "token",
        provider: "github-copilot",
        tokenRef: { source: "env", provider: "default", id: "GITHUB_TOKEN" },
      },
    };
    mockOrder = ["github-copilot:default"];

    const result = await resolveAuthLabel(
      "github-copilot",
      {} as OpenClawConfig,
      "/tmp/models.json",
      undefined,
      "compact",
    );

    (expect* result.label).is("github-copilot:default token (ref)");
  });

  (deftest "uses token:ref instead of token:missing in verbose mode", async () => {
    mockStore.profiles = {
      "github-copilot:default": {
        type: "token",
        provider: "github-copilot",
        tokenRef: { source: "env", provider: "default", id: "GITHUB_TOKEN" },
      },
    };
    mockOrder = ["github-copilot:default"];

    const result = await resolveAuthLabel(
      "github-copilot",
      {} as OpenClawConfig,
      "/tmp/models.json",
      undefined,
      "verbose",
    );

    (expect* result.label).contains("github-copilot:default=token:ref");
    (expect* result.label).not.contains("token:missing");
  });
});
