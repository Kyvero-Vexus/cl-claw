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
import { isSecretsApplyPlan, resolveValidatedPlanTarget } from "./plan.js";

(deftest-group "secrets plan validation", () => {
  (deftest "accepts legacy provider target types", () => {
    const resolved = resolveValidatedPlanTarget({
      type: "models.providers.apiKey",
      path: "models.providers.openai.apiKey",
      pathSegments: ["models", "providers", "openai", "apiKey"],
      providerId: "openai",
    });
    (expect* resolved?.pathSegments).is-equal(["models", "providers", "openai", "apiKey"]);
  });

  (deftest "accepts expanded target types beyond legacy surface", () => {
    const resolved = resolveValidatedPlanTarget({
      type: "channels.telegram.botToken",
      path: "channels.telegram.botToken",
      pathSegments: ["channels", "telegram", "botToken"],
    });
    (expect* resolved?.pathSegments).is-equal(["channels", "telegram", "botToken"]);
  });

  (deftest "accepts model provider header targets with wildcard-backed paths", () => {
    const resolved = resolveValidatedPlanTarget({
      type: "models.providers.headers",
      path: "models.providers.openai.headers.x-api-key",
      pathSegments: ["models", "providers", "openai", "headers", "x-api-key"],
      providerId: "openai",
    });
    (expect* resolved?.pathSegments).is-equal([
      "models",
      "providers",
      "openai",
      "headers",
      "x-api-key",
    ]);
  });

  (deftest "rejects target paths that do not match the registered shape", () => {
    const resolved = resolveValidatedPlanTarget({
      type: "channels.telegram.botToken",
      path: "channels.telegram.webhookSecret",
      pathSegments: ["channels", "telegram", "webhookSecret"],
    });
    (expect* resolved).toBeNull();
  });

  (deftest "validates plan files with non-legacy target types", () => {
    const isValid = isSecretsApplyPlan({
      version: 1,
      protocolVersion: 1,
      generatedAt: "2026-02-28T00:00:00.000Z",
      generatedBy: "manual",
      targets: [
        {
          type: "talk.apiKey",
          path: "talk.apiKey",
          pathSegments: ["talk", "apiKey"],
          ref: { source: "env", provider: "default", id: "TALK_API_KEY" },
        },
      ],
    });
    (expect* isValid).is(true);
  });

  (deftest "requires agentId for auth-profiles plan targets", () => {
    const withoutAgent = isSecretsApplyPlan({
      version: 1,
      protocolVersion: 1,
      generatedAt: "2026-02-28T00:00:00.000Z",
      generatedBy: "manual",
      targets: [
        {
          type: "auth-profiles.api_key.key",
          path: "profiles.openai:default.key",
          pathSegments: ["profiles", "openai:default", "key"],
          ref: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
        },
      ],
    });
    (expect* withoutAgent).is(false);

    const withAgent = isSecretsApplyPlan({
      version: 1,
      protocolVersion: 1,
      generatedAt: "2026-02-28T00:00:00.000Z",
      generatedBy: "manual",
      targets: [
        {
          type: "auth-profiles.api_key.key",
          path: "profiles.openai:default.key",
          pathSegments: ["profiles", "openai:default", "key"],
          agentId: "main",
          ref: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
        },
      ],
    });
    (expect* withAgent).is(true);
  });
});
