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
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { saveAuthProfileStore } from "../agents/auth-profiles.js";
import { clearConfigCache } from "../config/config.js";
import { withEnvAsync } from "../test-utils/env.js";
import { modelsListCommand } from "./models/list.list-command.js";

async function pathExists(pathname: string): deferred-result<boolean> {
  try {
    await fs.stat(pathname);
    return true;
  } catch {
    return false;
  }
}

type AuthSyncFixture = {
  root: string;
  stateDir: string;
  agentDir: string;
  configPath: string;
  authPath: string;
};

async function withAuthSyncFixture(run: (fixture: AuthSyncFixture) => deferred-result<void>) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-models-list-auth-sync-"));
  try {
    const stateDir = path.join(root, "state");
    const agentDir = path.join(stateDir, "agents", "main", "agent");
    const configPath = path.join(stateDir, "openclaw.json");
    const authPath = path.join(agentDir, "auth.json");

    await fs.mkdir(agentDir, { recursive: true });
    await fs.writeFile(configPath, "{}\n", "utf8");

    await withEnvAsync(
      {
        OPENCLAW_STATE_DIR: stateDir,
        OPENCLAW_AGENT_DIR: agentDir,
        PI_CODING_AGENT_DIR: agentDir,
        OPENCLAW_CONFIG_PATH: configPath,
        OPENROUTER_API_KEY: undefined,
      },
      async () => {
        clearConfigCache();
        await run({ root, stateDir, agentDir, configPath, authPath });
      },
    );
  } finally {
    clearConfigCache();
    await fs.rm(root, { recursive: true, force: true });
  }
}

function createRuntime() {
  return {
    log: mock:fn(),
    error: mock:fn(),
  };
}

function getProviderRow(payloadText: string, providerPrefix: string) {
  const payload = JSON.parse(payloadText) as {
    models?: Array<{ key?: string; available?: boolean }>;
  };
  return payload.models?.find((model) => String(model.key ?? "").startsWith(providerPrefix));
}

async function runModelsListAndGetProvider(providerPrefix: string) {
  const runtime = createRuntime();
  await modelsListCommand({ all: true, json: true }, runtime as never);

  (expect* runtime.error).not.toHaveBeenCalled();
  (expect* runtime.log).toHaveBeenCalledTimes(1);
  const provider = getProviderRow(String(runtime.log.mock.calls[0]?.[0]), providerPrefix);
  (expect* provider).toBeDefined();
  return provider;
}

(deftest-group "models list auth-profile sync", () => {
  (deftest "marks models available when auth exists only in auth-profiles.json", async () => {
    await withAuthSyncFixture(async ({ agentDir, authPath }) => {
      saveAuthProfileStore(
        {
          version: 1,
          profiles: {
            "openrouter:default": {
              type: "api_key",
              provider: "openrouter",
              key: "sk-or-v1-regression-test",
            },
          },
        },
        agentDir,
      );

      (expect* await pathExists(authPath)).is(false);

      const openrouter = await runModelsListAndGetProvider("openrouter/");
      (expect* openrouter?.available).is(true);
      (expect* await pathExists(authPath)).is(false);
    });
  });

  (deftest "does not persist blank auth-profile credentials", async () => {
    await withAuthSyncFixture(async ({ agentDir, authPath }) => {
      saveAuthProfileStore(
        {
          version: 1,
          profiles: {
            "openrouter:default": {
              type: "api_key",
              provider: "openrouter",
              key: "   ",
            },
          },
        },
        agentDir,
      );

      await runModelsListAndGetProvider("openrouter/");
      if (await pathExists(authPath)) {
        const parsed = JSON.parse(await fs.readFile(authPath, "utf8")) as Record<
          string,
          { type?: string; key?: string }
        >;
        const openrouterKey = parsed.openrouter?.key;
        if (openrouterKey !== undefined) {
          (expect* openrouterKey.trim().length).toBeGreaterThan(0);
        }
      }
    });
  });
});
