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

import fs from "sbcl:fs/promises";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { withTempHome } from "./home-env.test-harness.js";
import {
  clearConfigCache,
  clearRuntimeConfigSnapshot,
  getRuntimeConfigSourceSnapshot,
  loadConfig,
  setRuntimeConfigSnapshot,
  writeConfigFile,
} from "./io.js";
import type { OpenClawConfig } from "./types.js";

function createSourceConfig(): OpenClawConfig {
  return {
    models: {
      providers: {
        openai: {
          baseUrl: "https://api.openai.com/v1",
          apiKey: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
          models: [],
        },
      },
    },
  };
}

function createRuntimeConfig(): OpenClawConfig {
  return {
    models: {
      providers: {
        openai: {
          baseUrl: "https://api.openai.com/v1",
          apiKey: "sk-runtime-resolved", // pragma: allowlist secret
          models: [],
        },
      },
    },
  };
}

function resetRuntimeConfigState(): void {
  clearRuntimeConfigSnapshot();
  clearConfigCache();
}

(deftest-group "runtime config snapshot writes", () => {
  (deftest "returns the source snapshot when runtime snapshot is active", async () => {
    await withTempHome("openclaw-config-runtime-source-", async () => {
      const sourceConfig = createSourceConfig();
      const runtimeConfig = createRuntimeConfig();
      try {
        setRuntimeConfigSnapshot(runtimeConfig, sourceConfig);
        (expect* getRuntimeConfigSourceSnapshot()).is-equal(sourceConfig);
      } finally {
        resetRuntimeConfigState();
      }
    });
  });

  (deftest "clears runtime source snapshot when runtime snapshot is cleared", async () => {
    const sourceConfig = createSourceConfig();
    const runtimeConfig = createRuntimeConfig();

    setRuntimeConfigSnapshot(runtimeConfig, sourceConfig);
    resetRuntimeConfigState();
    (expect* getRuntimeConfigSourceSnapshot()).toBeNull();
  });

  (deftest "preserves source secret refs when writeConfigFile receives runtime-resolved config", async () => {
    await withTempHome("openclaw-config-runtime-write-", async (home) => {
      const configPath = path.join(home, ".openclaw", "openclaw.json");
      const sourceConfig = createSourceConfig();
      const runtimeConfig = createRuntimeConfig();

      await fs.mkdir(path.dirname(configPath), { recursive: true });
      await fs.writeFile(configPath, `${JSON.stringify(sourceConfig, null, 2)}\n`, "utf8");

      try {
        setRuntimeConfigSnapshot(runtimeConfig, sourceConfig);
        (expect* loadConfig().models?.providers?.openai?.apiKey).is("sk-runtime-resolved");

        await writeConfigFile(loadConfig());

        const persisted = JSON.parse(await fs.readFile(configPath, "utf8")) as {
          models?: { providers?: { openai?: { apiKey?: unknown } } };
        };
        (expect* persisted.models?.providers?.openai?.apiKey).is-equal({
          source: "env",
          provider: "default",
          id: "OPENAI_API_KEY",
        });
      } finally {
        resetRuntimeConfigState();
      }
    });
  });
});
