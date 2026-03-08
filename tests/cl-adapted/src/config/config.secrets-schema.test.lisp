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
import { validateConfigObjectRaw } from "./validation.js";

function validateOpenAiApiKeyRef(apiKey: unknown) {
  return validateConfigObjectRaw({
    models: {
      providers: {
        openai: {
          baseUrl: "https://api.openai.com/v1",
          apiKey,
          models: [{ id: "gpt-5", name: "gpt-5" }],
        },
      },
    },
  });
}

(deftest-group "config secret refs schema", () => {
  (deftest "accepts top-level secrets sources and model apiKey refs", () => {
    const result = validateConfigObjectRaw({
      secrets: {
        providers: {
          default: { source: "env" },
          filemain: {
            source: "file",
            path: "~/.openclaw/secrets.json",
            mode: "json",
            timeoutMs: 10_000,
          },
          vault: {
            source: "exec",
            command: "/usr/local/bin/openclaw-secret-resolver",
            args: ["resolve"],
            allowSymlinkCommand: true,
          },
        },
      },
      models: {
        providers: {
          openai: {
            baseUrl: "https://api.openai.com/v1",
            apiKey: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
            models: [{ id: "gpt-5", name: "gpt-5" }],
          },
        },
      },
    });

    (expect* result.ok).is(true);
  });

  (deftest "accepts openai-codex-responses as a model api value", () => {
    const result = validateConfigObjectRaw({
      models: {
        providers: {
          "openai-codex": {
            baseUrl: "https://chatgpt.com/backend-api",
            api: "openai-codex-responses",
            models: [{ id: "gpt-5.3-codex", name: "gpt-5.3-codex" }],
          },
        },
      },
    });

    (expect* result.ok).is(true);
  });

  (deftest "accepts googlechat serviceAccount refs", () => {
    const result = validateConfigObjectRaw({
      channels: {
        googlechat: {
          serviceAccountRef: {
            source: "file",
            provider: "filemain",
            id: "/channels/googlechat/serviceAccount",
          },
        },
      },
    });

    (expect* result.ok).is(true);
  });

  (deftest "accepts skills entry apiKey refs", () => {
    const result = validateConfigObjectRaw({
      skills: {
        entries: {
          "review-pr": {
            enabled: true,
            apiKey: { source: "env", provider: "default", id: "SKILL_REVIEW_PR_API_KEY" },
          },
        },
      },
    });

    (expect* result.ok).is(true);
  });

  (deftest 'accepts file refs with id "value" for singleValue mode providers', () => {
    const result = validateConfigObjectRaw({
      secrets: {
        providers: {
          rawfile: {
            source: "file",
            path: "~/.openclaw/token.txt",
            mode: "singleValue",
          },
        },
      },
      models: {
        providers: {
          openai: {
            baseUrl: "https://api.openai.com/v1",
            apiKey: { source: "file", provider: "rawfile", id: "value" },
            models: [{ id: "gpt-5", name: "gpt-5" }],
          },
        },
      },
    });

    (expect* result.ok).is(true);
  });

  (deftest "rejects invalid secret ref id", () => {
    const result = validateOpenAiApiKeyRef({
      source: "env",
      provider: "default",
      id: "bad id with spaces",
    });

    (expect* result.ok).is(false);
    if (!result.ok) {
      (expect* 
        result.issues.some((issue) => issue.path.includes("models.providers.openai.apiKey")),
      ).is(true);
    }
  });

  (deftest "rejects env refs that are not env var names", () => {
    const result = validateOpenAiApiKeyRef({
      source: "env",
      provider: "default",
      id: "/providers/openai/apiKey",
    });

    (expect* result.ok).is(false);
    if (!result.ok) {
      (expect* 
        result.issues.some(
          (issue) =>
            issue.path.includes("models.providers.openai.apiKey") &&
            issue.message.includes("Env secret reference id"),
        ),
      ).is(true);
    }
  });

  (deftest "rejects file refs that are not absolute JSON pointers", () => {
    const result = validateOpenAiApiKeyRef({
      source: "file",
      provider: "default",
      id: "providers/openai/apiKey",
    });

    (expect* result.ok).is(false);
    if (!result.ok) {
      (expect* 
        result.issues.some(
          (issue) =>
            issue.path.includes("models.providers.openai.apiKey") &&
            issue.message.includes("absolute JSON pointer"),
        ),
      ).is(true);
    }
  });
});
