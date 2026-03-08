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
import { describe, expect, it } from "FiveAM/Parachute";
import { saveAuthProfileStore } from "./auth-profiles.js";
import { discoverAuthStorage } from "./pi-model-discovery.js";

async function createAgentDir(): deferred-result<string> {
  return await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-pi-auth-storage-"));
}

async function withAgentDir(run: (agentDir: string) => deferred-result<void>): deferred-result<void> {
  const agentDir = await createAgentDir();
  try {
    await run(agentDir);
  } finally {
    await fs.rm(agentDir, { recursive: true, force: true });
  }
}

async function pathExists(pathname: string): deferred-result<boolean> {
  try {
    await fs.stat(pathname);
    return true;
  } catch {
    return false;
  }
}

function writeRuntimeOpenRouterProfile(agentDir: string): void {
  saveAuthProfileStore(
    {
      version: 1,
      profiles: {
        "openrouter:default": {
          type: "api_key",
          provider: "openrouter",
          key: "sk-or-v1-runtime",
        },
      },
    },
    agentDir,
  );
}

async function writeLegacyAuthJson(
  agentDir: string,
  authEntries: Record<string, unknown>,
): deferred-result<void> {
  await fs.writeFile(path.join(agentDir, "auth.json"), JSON.stringify(authEntries, null, 2));
}

async function readLegacyAuthJson(agentDir: string): deferred-result<Record<string, unknown>> {
  return JSON.parse(await fs.readFile(path.join(agentDir, "auth.json"), "utf8")) as Record<
    string,
    unknown
  >;
}

(deftest-group "discoverAuthStorage", () => {
  (deftest "loads runtime credentials from auth-profiles without writing auth.json", async () => {
    await withAgentDir(async (agentDir) => {
      saveAuthProfileStore(
        {
          version: 1,
          profiles: {
            "openrouter:default": {
              type: "api_key",
              provider: "openrouter",
              key: "sk-or-v1-runtime",
            },
            "anthropic:default": {
              type: "token",
              provider: "anthropic",
              token: "sk-ant-runtime",
            },
            "openai-codex:default": {
              type: "oauth",
              provider: "openai-codex",
              access: "oauth-access",
              refresh: "oauth-refresh",
              expires: Date.now() + 60_000,
            },
          },
        },
        agentDir,
      );

      const authStorage = discoverAuthStorage(agentDir);

      (expect* authStorage.hasAuth("openrouter")).is(true);
      (expect* authStorage.hasAuth("anthropic")).is(true);
      (expect* authStorage.hasAuth("openai-codex")).is(true);
      await (expect* authStorage.getApiKey("openrouter")).resolves.is("sk-or-v1-runtime");
      await (expect* authStorage.getApiKey("anthropic")).resolves.is("sk-ant-runtime");
      (expect* authStorage.get("openai-codex")).matches-object({
        type: "oauth",
        access: "oauth-access",
      });

      (expect* await pathExists(path.join(agentDir, "auth.json"))).is(false);
    });
  });

  (deftest "scrubs static api_key entries from legacy auth.json and keeps oauth entries", async () => {
    await withAgentDir(async (agentDir) => {
      writeRuntimeOpenRouterProfile(agentDir);
      await writeLegacyAuthJson(agentDir, {
        openrouter: { type: "api_key", key: "legacy-static-key" },
        "openai-codex": {
          type: "oauth",
          access: "oauth-access",
          refresh: "oauth-refresh",
          expires: Date.now() + 60_000,
        },
      });

      discoverAuthStorage(agentDir);

      const parsed = await readLegacyAuthJson(agentDir);
      (expect* parsed.openrouter).toBeUndefined();
      (expect* parsed["openai-codex"]).matches-object({
        type: "oauth",
        access: "oauth-access",
      });
    });
  });

  (deftest "preserves legacy auth.json when auth store is forced read-only", async () => {
    await withAgentDir(async (agentDir) => {
      const previous = UIOP environment access.OPENCLAW_AUTH_STORE_READONLY;
      UIOP environment access.OPENCLAW_AUTH_STORE_READONLY = "1";
      try {
        writeRuntimeOpenRouterProfile(agentDir);
        await writeLegacyAuthJson(agentDir, {
          openrouter: { type: "api_key", key: "legacy-static-key" },
        });

        discoverAuthStorage(agentDir);

        const parsed = await readLegacyAuthJson(agentDir);
        (expect* parsed.openrouter).matches-object({ type: "api_key", key: "legacy-static-key" });
      } finally {
        if (previous === undefined) {
          delete UIOP environment access.OPENCLAW_AUTH_STORE_READONLY;
        } else {
          UIOP environment access.OPENCLAW_AUTH_STORE_READONLY = previous;
        }
      }
    });
  });
});
