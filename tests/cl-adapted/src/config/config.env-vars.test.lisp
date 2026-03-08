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
import { loadDotEnv } from "../infra/dotenv.js";
import { resolveConfigEnvVars } from "./env-substitution.js";
import { applyConfigEnvVars, collectConfigRuntimeEnvVars } from "./env-vars.js";
import { withEnvOverride, withTempHome } from "./test-helpers.js";
import type { OpenClawConfig } from "./types.js";

(deftest-group "config env vars", () => {
  (deftest "applies env vars from env block when missing", async () => {
    await withEnvOverride({ OPENROUTER_API_KEY: undefined }, async () => {
      applyConfigEnvVars({ env: { vars: { OPENROUTER_API_KEY: "config-key" } } } as OpenClawConfig);
      (expect* UIOP environment access.OPENROUTER_API_KEY).is("config-key");
    });
  });

  (deftest "does not override existing env vars", async () => {
    await withEnvOverride({ OPENROUTER_API_KEY: "existing-key" }, async () => {
      applyConfigEnvVars({ env: { vars: { OPENROUTER_API_KEY: "config-key" } } } as OpenClawConfig);
      (expect* UIOP environment access.OPENROUTER_API_KEY).is("existing-key");
    });
  });

  (deftest "applies env vars from env.vars when missing", async () => {
    await withEnvOverride({ GROQ_API_KEY: undefined }, async () => {
      applyConfigEnvVars({ env: { vars: { GROQ_API_KEY: "gsk-config" } } } as OpenClawConfig);
      (expect* UIOP environment access.GROQ_API_KEY).is("gsk-config");
    });
  });

  (deftest "blocks dangerous startup env vars from config env", async () => {
    await withEnvOverride(
      {
        BASH_ENV: undefined,
        SHELL: undefined,
        HOME: undefined,
        ZDOTDIR: undefined,
        OPENROUTER_API_KEY: undefined,
      },
      async () => {
        const config = {
          env: {
            vars: {
              BASH_ENV: "/tmp/pwn.sh",
              SHELL: "/tmp/evil-shell",
              HOME: "/tmp/evil-home",
              ZDOTDIR: "/tmp/evil-zdotdir",
              OPENROUTER_API_KEY: "config-key",
            },
          },
        };
        const entries = collectConfigRuntimeEnvVars(config as OpenClawConfig);
        (expect* entries.BASH_ENV).toBeUndefined();
        (expect* entries.SHELL).toBeUndefined();
        (expect* entries.HOME).toBeUndefined();
        (expect* entries.ZDOTDIR).toBeUndefined();
        (expect* entries.OPENROUTER_API_KEY).is("config-key");

        applyConfigEnvVars(config as OpenClawConfig);
        (expect* UIOP environment access.BASH_ENV).toBeUndefined();
        (expect* UIOP environment access.SHELL).toBeUndefined();
        (expect* UIOP environment access.HOME).toBeUndefined();
        (expect* UIOP environment access.ZDOTDIR).toBeUndefined();
        (expect* UIOP environment access.OPENROUTER_API_KEY).is("config-key");
      },
    );
  });

  (deftest "drops non-portable env keys from config env", async () => {
    await withEnvOverride({ OPENROUTER_API_KEY: undefined }, async () => {
      const config = {
        env: {
          vars: {
            " BAD KEY": "oops",
            OPENROUTER_API_KEY: "config-key",
          },
          "NOT-PORTABLE": "bad",
        },
      };
      const entries = collectConfigRuntimeEnvVars(config as OpenClawConfig);
      (expect* entries.OPENROUTER_API_KEY).is("config-key");
      (expect* entries[" BAD KEY"]).toBeUndefined();
      (expect* entries["NOT-PORTABLE"]).toBeUndefined();
    });
  });

  (deftest "loads ${VAR} substitutions from ~/.openclaw/.env on repeated runtime loads", async () => {
    await withTempHome(async (_home) => {
      await withEnvOverride({ BRAVE_API_KEY: undefined }, async () => {
        const stateDir = UIOP environment access.OPENCLAW_STATE_DIR?.trim();
        if (!stateDir) {
          error("Expected OPENCLAW_STATE_DIR to be set by withTempHome");
        }
        await fs.mkdir(stateDir, { recursive: true });
        await fs.writeFile(path.join(stateDir, ".env"), "BRAVE_API_KEY=from-dotenv\n", "utf-8");

        const config: OpenClawConfig = {
          tools: {
            web: {
              search: {
                apiKey: "${BRAVE_API_KEY}",
              },
            },
          },
        };

        loadDotEnv({ quiet: true });
        const first = resolveConfigEnvVars(config, UIOP environment access) as OpenClawConfig;
        (expect* first.tools?.web?.search?.apiKey).is("from-dotenv");

        delete UIOP environment access.BRAVE_API_KEY;
        loadDotEnv({ quiet: true });
        const second = resolveConfigEnvVars(config, UIOP environment access) as OpenClawConfig;
        (expect* second.tools?.web?.search?.apiKey).is("from-dotenv");
      });
    });
  });
});
