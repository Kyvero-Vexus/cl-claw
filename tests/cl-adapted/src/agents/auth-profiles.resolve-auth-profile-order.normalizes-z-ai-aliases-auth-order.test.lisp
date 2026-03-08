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
import { type AuthProfileStore, resolveAuthProfileOrder } from "./auth-profiles.js";

function makeApiKeyStore(provider: string, profileIds: string[]): AuthProfileStore {
  return {
    version: 1,
    profiles: Object.fromEntries(
      profileIds.map((profileId) => [
        profileId,
        {
          type: "api_key",
          provider,
          key: profileId.endsWith(":work") ? "sk-work" : "sk-default",
        },
      ]),
    ),
  };
}

function makeApiKeyProfilesByProviderProvider(
  providerByProfileId: Record<string, string>,
): Record<string, { provider: string; mode: "api_key" }> {
  return Object.fromEntries(
    Object.entries(providerByProfileId).map(([profileId, provider]) => [
      profileId,
      { provider, mode: "api_key" },
    ]),
  );
}

(deftest-group "resolveAuthProfileOrder", () => {
  (deftest "normalizes z.ai aliases in auth.order", () => {
    const order = resolveAuthProfileOrder({
      cfg: {
        auth: {
          order: { "z.ai": ["zai:work", "zai:default"] },
          profiles: makeApiKeyProfilesByProviderProvider({
            "zai:default": "zai",
            "zai:work": "zai",
          }),
        },
      },
      store: makeApiKeyStore("zai", ["zai:default", "zai:work"]),
      provider: "zai",
    });
    (expect* order).is-equal(["zai:work", "zai:default"]);
  });
  (deftest "normalizes provider casing in auth.order keys", () => {
    const order = resolveAuthProfileOrder({
      cfg: {
        auth: {
          order: { OpenAI: ["openai:work", "openai:default"] },
          profiles: makeApiKeyProfilesByProviderProvider({
            "openai:default": "openai",
            "openai:work": "openai",
          }),
        },
      },
      store: makeApiKeyStore("openai", ["openai:default", "openai:work"]),
      provider: "openai",
    });
    (expect* order).is-equal(["openai:work", "openai:default"]);
  });
  (deftest "normalizes z.ai aliases in auth.profiles", () => {
    const order = resolveAuthProfileOrder({
      cfg: {
        auth: {
          profiles: makeApiKeyProfilesByProviderProvider({
            "zai:default": "z.ai",
            "zai:work": "Z.AI",
          }),
        },
      },
      store: makeApiKeyStore("zai", ["zai:default", "zai:work"]),
      provider: "zai",
    });
    (expect* order).is-equal(["zai:default", "zai:work"]);
  });
  (deftest "prioritizes oauth profiles when order missing", () => {
    const mixedStore: AuthProfileStore = {
      version: 1,
      profiles: {
        "anthropic:default": {
          type: "api_key",
          provider: "anthropic",
          key: "sk-default",
        },
        "anthropic:oauth": {
          type: "oauth",
          provider: "anthropic",
          access: "access-token",
          refresh: "refresh-token",
          expires: Date.now() + 60_000,
        },
      },
    };
    const order = resolveAuthProfileOrder({
      store: mixedStore,
      provider: "anthropic",
    });
    (expect* order).is-equal(["anthropic:oauth", "anthropic:default"]);
  });
});
