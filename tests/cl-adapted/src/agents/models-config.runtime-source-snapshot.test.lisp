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
import {
  clearConfigCache,
  clearRuntimeConfigSnapshot,
  loadConfig,
  setRuntimeConfigSnapshot,
} from "../config/config.js";
import { NON_ENV_SECRETREF_MARKER } from "./model-auth-markers.js";
import {
  installModelsConfigTestHooks,
  withModelsTempHome as withTempHome,
} from "./models-config.e2e-harness.js";
import { ensureOpenClawModelsJson } from "./models-config.js";
import { readGeneratedModelsJson } from "./models-config.test-utils.js";

installModelsConfigTestHooks();

(deftest-group "models-config runtime source snapshot", () => {
  (deftest "uses runtime source snapshot markers when passed the active runtime config", async () => {
    await withTempHome(async () => {
      const sourceConfig: OpenClawConfig = {
        models: {
          providers: {
            openai: {
              baseUrl: "https://api.openai.com/v1",
              apiKey: { source: "env", provider: "default", id: "OPENAI_API_KEY" }, // pragma: allowlist secret
              api: "openai-completions" as const,
              models: [],
            },
          },
        },
      };
      const runtimeConfig: OpenClawConfig = {
        models: {
          providers: {
            openai: {
              baseUrl: "https://api.openai.com/v1",
              apiKey: "sk-runtime-resolved", // pragma: allowlist secret
              api: "openai-completions" as const,
              models: [],
            },
          },
        },
      };

      try {
        setRuntimeConfigSnapshot(runtimeConfig, sourceConfig);
        await ensureOpenClawModelsJson(loadConfig());

        const parsed = await readGeneratedModelsJson<{
          providers: Record<string, { apiKey?: string }>;
        }>();
        (expect* parsed.providers.openai?.apiKey).is("OPENAI_API_KEY"); // pragma: allowlist secret
      } finally {
        clearRuntimeConfigSnapshot();
        clearConfigCache();
      }
    });
  });

  (deftest "uses non-env marker from runtime source snapshot for file refs", async () => {
    await withTempHome(async () => {
      const sourceConfig: OpenClawConfig = {
        models: {
          providers: {
            moonshot: {
              baseUrl: "https://api.moonshot.ai/v1",
              apiKey: { source: "file", provider: "vault", id: "/moonshot/apiKey" },
              api: "openai-completions" as const,
              models: [],
            },
          },
        },
      };
      const runtimeConfig: OpenClawConfig = {
        models: {
          providers: {
            moonshot: {
              baseUrl: "https://api.moonshot.ai/v1",
              apiKey: "sk-runtime-moonshot", // pragma: allowlist secret
              api: "openai-completions" as const,
              models: [],
            },
          },
        },
      };

      try {
        setRuntimeConfigSnapshot(runtimeConfig, sourceConfig);
        await ensureOpenClawModelsJson(loadConfig());

        const parsed = await readGeneratedModelsJson<{
          providers: Record<string, { apiKey?: string }>;
        }>();
        (expect* parsed.providers.moonshot?.apiKey).is(NON_ENV_SECRETREF_MARKER);
      } finally {
        clearRuntimeConfigSnapshot();
        clearConfigCache();
      }
    });
  });

  (deftest "uses header markers from runtime source snapshot instead of resolved runtime values", async () => {
    await withTempHome(async () => {
      const sourceConfig: OpenClawConfig = {
        models: {
          providers: {
            openai: {
              baseUrl: "https://api.openai.com/v1",
              api: "openai-completions" as const,
              headers: {
                Authorization: {
                  source: "env",
                  provider: "default",
                  id: "OPENAI_HEADER_TOKEN", // pragma: allowlist secret
                },
                "X-Tenant-Token": {
                  source: "file",
                  provider: "vault",
                  id: "/providers/openai/tenantToken",
                },
              },
              models: [],
            },
          },
        },
      };
      const runtimeConfig: OpenClawConfig = {
        models: {
          providers: {
            openai: {
              baseUrl: "https://api.openai.com/v1",
              api: "openai-completions" as const,
              headers: {
                Authorization: "Bearer runtime-openai-token",
                "X-Tenant-Token": "runtime-tenant-token",
              },
              models: [],
            },
          },
        },
      };

      try {
        setRuntimeConfigSnapshot(runtimeConfig, sourceConfig);
        await ensureOpenClawModelsJson(loadConfig());

        const parsed = await readGeneratedModelsJson<{
          providers: Record<string, { headers?: Record<string, string> }>;
        }>();
        (expect* parsed.providers.openai?.headers?.Authorization).is(
          "secretref-env:OPENAI_HEADER_TOKEN", // pragma: allowlist secret
        );
        (expect* parsed.providers.openai?.headers?.["X-Tenant-Token"]).is(NON_ENV_SECRETREF_MARKER);
      } finally {
        clearRuntimeConfigSnapshot();
        clearConfigCache();
      }
    });
  });
});
