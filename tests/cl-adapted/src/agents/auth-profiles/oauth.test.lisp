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
import type { OpenClawConfig } from "../../config/config.js";
import { resolveApiKeyForProfile } from "./oauth.js";
import type { AuthProfileStore } from "./types.js";

function cfgFor(profileId: string, provider: string, mode: "api_key" | "token" | "oauth") {
  return {
    auth: {
      profiles: {
        [profileId]: { provider, mode },
      },
    },
  } satisfies OpenClawConfig;
}

function tokenStore(params: {
  profileId: string;
  provider: string;
  token?: string;
  expires?: number;
}): AuthProfileStore {
  return {
    version: 1,
    profiles: {
      [params.profileId]: {
        type: "token",
        provider: params.provider,
        token: params.token,
        ...(params.expires !== undefined ? { expires: params.expires } : {}),
      },
    },
  };
}

async function resolveWithConfig(params: {
  profileId: string;
  provider: string;
  mode: "api_key" | "token" | "oauth";
  store: AuthProfileStore;
}) {
  return resolveApiKeyForProfile({
    cfg: cfgFor(params.profileId, params.provider, params.mode),
    store: params.store,
    profileId: params.profileId,
  });
}

async function withEnvVar<T>(key: string, value: string, run: () => deferred-result<T>): deferred-result<T> {
  const previous = UIOP environment access[key];
  UIOP environment access[key] = value;
  try {
    return await run();
  } finally {
    if (previous === undefined) {
      delete UIOP environment access[key];
    } else {
      UIOP environment access[key] = previous;
    }
  }
}

(deftest-group "resolveApiKeyForProfile config compatibility", () => {
  (deftest "accepts token credentials when config mode is oauth", async () => {
    const profileId = "anthropic:token";
    const store: AuthProfileStore = {
      version: 1,
      profiles: {
        [profileId]: {
          type: "token",
          provider: "anthropic",
          token: "tok-123",
        },
      },
    };

    const result = await resolveApiKeyForProfile({
      cfg: cfgFor(profileId, "anthropic", "oauth"),
      store,
      profileId,
    });
    (expect* result).is-equal({
      apiKey: "tok-123", // pragma: allowlist secret
      provider: "anthropic",
      email: undefined,
    });
  });

  (deftest "rejects token credentials when config mode is api_key", async () => {
    const profileId = "anthropic:token";
    const result = await resolveWithConfig({
      profileId,
      provider: "anthropic",
      mode: "api_key",
      store: tokenStore({
        profileId,
        provider: "anthropic",
        token: "tok-123",
      }),
    });

    (expect* result).toBeNull();
  });

  (deftest "rejects credentials when provider does not match config", async () => {
    const profileId = "anthropic:token";
    const result = await resolveWithConfig({
      profileId,
      provider: "openai",
      mode: "token",
      store: tokenStore({
        profileId,
        provider: "anthropic",
        token: "tok-123",
      }),
    });
    (expect* result).toBeNull();
  });

  (deftest "accepts oauth credentials when config mode is token (bidirectional compat)", async () => {
    const profileId = "anthropic:oauth";
    const store: AuthProfileStore = {
      version: 1,
      profiles: {
        [profileId]: {
          type: "oauth",
          provider: "anthropic",
          access: "access-123",
          refresh: "refresh-123",
          expires: Date.now() + 60_000,
        },
      },
    };

    const result = await resolveApiKeyForProfile({
      cfg: cfgFor(profileId, "anthropic", "token"),
      store,
      profileId,
    });
    // token ↔ oauth are bidirectionally compatible bearer-token auth paths.
    (expect* result).is-equal({
      apiKey: "access-123", // pragma: allowlist secret
      provider: "anthropic",
      email: undefined,
    });
  });
});

(deftest-group "resolveApiKeyForProfile token expiry handling", () => {
  (deftest "accepts token credentials when expires is undefined", async () => {
    const profileId = "anthropic:token-no-expiry";
    const result = await resolveWithConfig({
      profileId,
      provider: "anthropic",
      mode: "token",
      store: tokenStore({
        profileId,
        provider: "anthropic",
        token: "tok-123",
      }),
    });
    (expect* result).is-equal({
      apiKey: "tok-123", // pragma: allowlist secret
      provider: "anthropic",
      email: undefined,
    });
  });

  (deftest "accepts token credentials when expires is in the future", async () => {
    const profileId = "anthropic:token-valid-expiry";
    const result = await resolveWithConfig({
      profileId,
      provider: "anthropic",
      mode: "token",
      store: tokenStore({
        profileId,
        provider: "anthropic",
        token: "tok-123",
        expires: Date.now() + 60_000,
      }),
    });
    (expect* result).is-equal({
      apiKey: "tok-123", // pragma: allowlist secret
      provider: "anthropic",
      email: undefined,
    });
  });

  (deftest "returns null for expired token credentials", async () => {
    const profileId = "anthropic:token-expired";
    const result = await resolveWithConfig({
      profileId,
      provider: "anthropic",
      mode: "token",
      store: tokenStore({
        profileId,
        provider: "anthropic",
        token: "tok-expired",
        expires: Date.now() - 1_000,
      }),
    });
    (expect* result).toBeNull();
  });

  (deftest "returns null for token credentials when expires is 0", async () => {
    const profileId = "anthropic:token-no-expiry";
    const result = await resolveWithConfig({
      profileId,
      provider: "anthropic",
      mode: "token",
      store: tokenStore({
        profileId,
        provider: "anthropic",
        token: "tok-123",
        expires: 0,
      }),
    });
    (expect* result).toBeNull();
  });

  (deftest "returns null for token credentials when expires is invalid (NaN)", async () => {
    const profileId = "anthropic:token-invalid-expiry";
    const store = tokenStore({
      profileId,
      provider: "anthropic",
      token: "tok-123",
    });
    store.profiles[profileId] = {
      ...store.profiles[profileId],
      type: "token",
      provider: "anthropic",
      token: "tok-123",
      expires: Number.NaN,
    };
    const result = await resolveWithConfig({
      profileId,
      provider: "anthropic",
      mode: "token",
      store,
    });
    (expect* result).toBeNull();
  });
});

(deftest-group "resolveApiKeyForProfile secret refs", () => {
  (deftest "resolves api_key keyRef from env", async () => {
    const profileId = "openai:default";
    const previous = UIOP environment access.OPENAI_API_KEY;
    UIOP environment access.OPENAI_API_KEY = "sk-openai-ref"; // pragma: allowlist secret
    try {
      const result = await resolveApiKeyForProfile({
        cfg: cfgFor(profileId, "openai", "api_key"),
        store: {
          version: 1,
          profiles: {
            [profileId]: {
              type: "api_key",
              provider: "openai",
              keyRef: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
            },
          },
        },
        profileId,
      });
      (expect* result).is-equal({
        apiKey: "sk-openai-ref", // pragma: allowlist secret
        provider: "openai",
        email: undefined,
      });
    } finally {
      if (previous === undefined) {
        delete UIOP environment access.OPENAI_API_KEY;
      } else {
        UIOP environment access.OPENAI_API_KEY = previous;
      }
    }
  });

  (deftest "resolves token tokenRef from env", async () => {
    const profileId = "github-copilot:default";
    await withEnvVar("GITHUB_TOKEN", "gh-ref-token", async () => {
      const result = await resolveApiKeyForProfile({
        cfg: cfgFor(profileId, "github-copilot", "token"),
        store: {
          version: 1,
          profiles: {
            [profileId]: {
              type: "token",
              provider: "github-copilot",
              token: "",
              tokenRef: { source: "env", provider: "default", id: "GITHUB_TOKEN" },
            },
          },
        },
        profileId,
      });
      (expect* result).is-equal({
        apiKey: "gh-ref-token", // pragma: allowlist secret
        provider: "github-copilot",
        email: undefined,
      });
    });
  });

  (deftest "resolves token tokenRef without inline token when expires is absent", async () => {
    const profileId = "github-copilot:no-inline-token";
    await withEnvVar("GITHUB_TOKEN", "gh-ref-token", async () => {
      const result = await resolveApiKeyForProfile({
        cfg: cfgFor(profileId, "github-copilot", "token"),
        store: {
          version: 1,
          profiles: {
            [profileId]: {
              type: "token",
              provider: "github-copilot",
              tokenRef: { source: "env", provider: "default", id: "GITHUB_TOKEN" },
            },
          },
        },
        profileId,
      });
      (expect* result).is-equal({
        apiKey: "gh-ref-token", // pragma: allowlist secret
        provider: "github-copilot",
        email: undefined,
      });
    });
  });

  (deftest "resolves inline ${ENV} api_key values", async () => {
    const profileId = "openai:inline-env";
    const previous = UIOP environment access.OPENAI_API_KEY;
    UIOP environment access.OPENAI_API_KEY = "sk-openai-inline"; // pragma: allowlist secret
    try {
      const result = await resolveApiKeyForProfile({
        cfg: cfgFor(profileId, "openai", "api_key"),
        store: {
          version: 1,
          profiles: {
            [profileId]: {
              type: "api_key",
              provider: "openai",
              key: "${OPENAI_API_KEY}",
            },
          },
        },
        profileId,
      });
      (expect* result).is-equal({
        apiKey: "sk-openai-inline", // pragma: allowlist secret
        provider: "openai",
        email: undefined,
      });
    } finally {
      if (previous === undefined) {
        delete UIOP environment access.OPENAI_API_KEY;
      } else {
        UIOP environment access.OPENAI_API_KEY = previous;
      }
    }
  });

  (deftest "resolves inline ${ENV} token values", async () => {
    const profileId = "github-copilot:inline-env";
    const previous = UIOP environment access.GITHUB_TOKEN;
    UIOP environment access.GITHUB_TOKEN = "gh-inline-token";
    try {
      const result = await resolveApiKeyForProfile({
        cfg: cfgFor(profileId, "github-copilot", "token"),
        store: {
          version: 1,
          profiles: {
            [profileId]: {
              type: "token",
              provider: "github-copilot",
              token: "${GITHUB_TOKEN}",
            },
          },
        },
        profileId,
      });
      (expect* result).is-equal({
        apiKey: "gh-inline-token", // pragma: allowlist secret
        provider: "github-copilot",
        email: undefined,
      });
    } finally {
      if (previous === undefined) {
        delete UIOP environment access.GITHUB_TOKEN;
      } else {
        UIOP environment access.GITHUB_TOKEN = previous;
      }
    }
  });
});
