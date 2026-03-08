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
import type { AuthProfileStore } from "./auth-profiles.js";
import { requireApiKey, resolveAwsSdkEnvVarName, resolveModelAuthMode } from "./model-auth.js";

(deftest-group "resolveAwsSdkEnvVarName", () => {
  (deftest "prefers bearer token over access keys and profile", () => {
    const env = {
      AWS_BEARER_TOKEN_BEDROCK: "bearer",
      AWS_ACCESS_KEY_ID: "access",
      AWS_SECRET_ACCESS_KEY: "secret", // pragma: allowlist secret
      AWS_PROFILE: "default",
    } as NodeJS.ProcessEnv;

    (expect* resolveAwsSdkEnvVarName(env)).is("AWS_BEARER_TOKEN_BEDROCK");
  });

  (deftest "uses access keys when bearer token is missing", () => {
    const env = {
      AWS_ACCESS_KEY_ID: "access",
      AWS_SECRET_ACCESS_KEY: "secret", // pragma: allowlist secret
      AWS_PROFILE: "default",
    } as NodeJS.ProcessEnv;

    (expect* resolveAwsSdkEnvVarName(env)).is("AWS_ACCESS_KEY_ID");
  });

  (deftest "uses profile when no bearer token or access keys exist", () => {
    const env = {
      AWS_PROFILE: "default",
    } as NodeJS.ProcessEnv;

    (expect* resolveAwsSdkEnvVarName(env)).is("AWS_PROFILE");
  });

  (deftest "returns undefined when no AWS auth env is set", () => {
    (expect* resolveAwsSdkEnvVarName({} as NodeJS.ProcessEnv)).toBeUndefined();
  });
});

(deftest-group "resolveModelAuthMode", () => {
  (deftest "returns mixed when provider has both token and api key profiles", () => {
    const store: AuthProfileStore = {
      version: 1,
      profiles: {
        "openai:token": {
          type: "token",
          provider: "openai",
          token: "token-value",
        },
        "openai:key": {
          type: "api_key",
          provider: "openai",
          key: "api-key",
        },
      },
    };

    (expect* resolveModelAuthMode("openai", undefined, store)).is("mixed");
  });

  (deftest "returns aws-sdk when provider auth is overridden", () => {
    (expect* 
      resolveModelAuthMode(
        "amazon-bedrock",
        {
          models: {
            providers: {
              "amazon-bedrock": {
                baseUrl: "https://bedrock-runtime.us-east-1.amazonaws.com",
                models: [],
                auth: "aws-sdk",
              },
            },
          },
        },
        { version: 1, profiles: {} },
      ),
    ).is("aws-sdk");
  });

  (deftest "returns aws-sdk for bedrock alias without explicit auth override", () => {
    (expect* resolveModelAuthMode("bedrock", undefined, { version: 1, profiles: {} })).is(
      "aws-sdk",
    );
  });

  (deftest "returns aws-sdk for aws-bedrock alias without explicit auth override", () => {
    (expect* resolveModelAuthMode("aws-bedrock", undefined, { version: 1, profiles: {} })).is(
      "aws-sdk",
    );
  });
});

(deftest-group "requireApiKey", () => {
  (deftest "normalizes line breaks in resolved API keys", () => {
    const key = requireApiKey(
      {
        apiKey: "\n sk-test-abc\r\n",
        source: "env: OPENAI_API_KEY",
        mode: "api-key",
      },
      "openai",
    );

    (expect* key).is("sk-test-abc");
  });

  (deftest "throws when no API key is present", () => {
    (expect* () =>
      requireApiKey(
        {
          source: "env: OPENAI_API_KEY",
          mode: "api-key",
        },
        "openai",
      ),
    ).signals-error('No API key resolved for provider "openai"');
  });
});
