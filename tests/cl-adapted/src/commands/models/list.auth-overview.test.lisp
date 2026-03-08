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
import { NON_ENV_SECRETREF_MARKER } from "../../agents/model-auth-markers.js";
import { resolveProviderAuthOverview } from "./list.auth-overview.js";

(deftest-group "resolveProviderAuthOverview", () => {
  (deftest "does not throw when token profile only has tokenRef", () => {
    const overview = resolveProviderAuthOverview({
      provider: "github-copilot",
      cfg: {},
      store: {
        version: 1,
        profiles: {
          "github-copilot:default": {
            type: "token",
            provider: "github-copilot",
            tokenRef: { source: "env", provider: "default", id: "GITHUB_TOKEN" },
          },
        },
      } as never,
      modelsPath: "/tmp/models.json",
    });

    (expect* overview.profiles.labels[0]).contains("token:ref(env:GITHUB_TOKEN)");
  });

  (deftest "renders marker-backed models.json auth as marker detail", () => {
    const overview = resolveProviderAuthOverview({
      provider: "openai",
      cfg: {
        models: {
          providers: {
            openai: {
              baseUrl: "https://api.openai.com/v1",
              api: "openai-completions",
              apiKey: NON_ENV_SECRETREF_MARKER,
              models: [],
            },
          },
        },
      } as never,
      store: { version: 1, profiles: {} } as never,
      modelsPath: "/tmp/models.json",
    });

    (expect* overview.effective.kind).is("models.json");
    (expect* overview.effective.detail).contains(`marker(${NON_ENV_SECRETREF_MARKER})`);
    (expect* overview.modelsJson?.value).contains(`marker(${NON_ENV_SECRETREF_MARKER})`);
  });

  (deftest "keeps env-var-shaped models.json values masked to avoid accidental plaintext exposure", () => {
    const overview = resolveProviderAuthOverview({
      provider: "openai",
      cfg: {
        models: {
          providers: {
            openai: {
              baseUrl: "https://api.openai.com/v1",
              api: "openai-completions",
              apiKey: "OPENAI_API_KEY", // pragma: allowlist secret
              models: [],
            },
          },
        },
      } as never,
      store: { version: 1, profiles: {} } as never,
      modelsPath: "/tmp/models.json",
    });

    (expect* overview.effective.kind).is("models.json");
    (expect* overview.effective.detail).not.contains("marker(");
    (expect* overview.effective.detail).not.contains("OPENAI_API_KEY");
  });
});
