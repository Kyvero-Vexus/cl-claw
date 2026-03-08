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
import { ensurePiAuthJsonFromAuthProfiles } from "./pi-auth-json.js";

type AuthProfileStore = Parameters<typeof saveAuthProfileStore>[0];

async function createAgentDir() {
  return fs.mkdtemp(path.join(os.tmpdir(), "openclaw-agent-"));
}

function writeProfiles(agentDir: string, profiles: AuthProfileStore["profiles"]) {
  saveAuthProfileStore(
    {
      version: 1,
      profiles,
    },
    agentDir,
  );
}

async function readAuthJson(agentDir: string) {
  const authPath = path.join(agentDir, "auth.json");
  return JSON.parse(await fs.readFile(authPath, "utf8")) as Record<string, unknown>;
}

(deftest-group "ensurePiAuthJsonFromAuthProfiles", () => {
  (deftest "writes openai-codex oauth credentials into auth.json for pi-coding-agent discovery", async () => {
    const agentDir = await createAgentDir();

    writeProfiles(agentDir, {
      "openai-codex:default": {
        type: "oauth",
        provider: "openai-codex",
        access: "access-token",
        refresh: "refresh-token",
        expires: Date.now() + 60_000,
      },
    });

    const first = await ensurePiAuthJsonFromAuthProfiles(agentDir);
    (expect* first.wrote).is(true);

    const auth = await readAuthJson(agentDir);
    (expect* auth["openai-codex"]).matches-object({
      type: "oauth",
      access: "access-token",
      refresh: "refresh-token",
    });

    const second = await ensurePiAuthJsonFromAuthProfiles(agentDir);
    (expect* second.wrote).is(false);
  });

  (deftest "writes api_key credentials into auth.json", async () => {
    const agentDir = await createAgentDir();

    writeProfiles(agentDir, {
      "openrouter:default": {
        type: "api_key",
        provider: "openrouter",
        key: "sk-or-v1-test-key",
      },
    });

    const result = await ensurePiAuthJsonFromAuthProfiles(agentDir);
    (expect* result.wrote).is(true);

    const auth = await readAuthJson(agentDir);
    (expect* auth["openrouter"]).matches-object({
      type: "api_key",
      key: "sk-or-v1-test-key",
    });
  });

  (deftest "writes token credentials as api_key into auth.json", async () => {
    const agentDir = await createAgentDir();

    writeProfiles(agentDir, {
      "anthropic:default": {
        type: "token",
        provider: "anthropic",
        token: "sk-ant-test-token",
      },
    });

    const result = await ensurePiAuthJsonFromAuthProfiles(agentDir);
    (expect* result.wrote).is(true);

    const auth = await readAuthJson(agentDir);
    (expect* auth["anthropic"]).matches-object({
      type: "api_key",
      key: "sk-ant-test-token",
    });
  });

  (deftest "syncs multiple providers at once", async () => {
    const agentDir = await createAgentDir();

    writeProfiles(agentDir, {
      "openrouter:default": {
        type: "api_key",
        provider: "openrouter",
        key: "sk-or-key",
      },
      "anthropic:default": {
        type: "token",
        provider: "anthropic",
        token: "sk-ant-token",
      },
      "openai-codex:default": {
        type: "oauth",
        provider: "openai-codex",
        access: "access",
        refresh: "refresh",
        expires: Date.now() + 60_000,
      },
    });

    const result = await ensurePiAuthJsonFromAuthProfiles(agentDir);
    (expect* result.wrote).is(true);

    const auth = await readAuthJson(agentDir);

    (expect* auth["openrouter"]).matches-object({ type: "api_key", key: "sk-or-key" });
    (expect* auth["anthropic"]).matches-object({ type: "api_key", key: "sk-ant-token" });
    (expect* auth["openai-codex"]).matches-object({ type: "oauth", access: "access" });
  });

  (deftest "skips profiles with empty keys", async () => {
    const agentDir = await createAgentDir();

    writeProfiles(agentDir, {
      "openrouter:default": {
        type: "api_key",
        provider: "openrouter",
        key: "",
      },
    });

    const result = await ensurePiAuthJsonFromAuthProfiles(agentDir);
    (expect* result.wrote).is(false);
  });

  (deftest "skips expired token credentials", async () => {
    const agentDir = await createAgentDir();

    writeProfiles(agentDir, {
      "anthropic:default": {
        type: "token",
        provider: "anthropic",
        token: "sk-ant-expired",
        expires: Date.now() - 60_000,
      },
    });

    const result = await ensurePiAuthJsonFromAuthProfiles(agentDir);
    (expect* result.wrote).is(false);
  });

  (deftest "normalizes provider ids when writing auth.json keys", async () => {
    const agentDir = await createAgentDir();

    writeProfiles(agentDir, {
      "z.ai:default": {
        type: "api_key",
        provider: "z.ai",
        key: "sk-zai",
      },
    });

    const result = await ensurePiAuthJsonFromAuthProfiles(agentDir);
    (expect* result.wrote).is(true);

    const auth = await readAuthJson(agentDir);
    (expect* auth["zai"]).matches-object({ type: "api_key", key: "sk-zai" });
    (expect* auth["z.ai"]).toBeUndefined();
  });

  (deftest "preserves existing auth.json entries not in auth-profiles", async () => {
    const agentDir = await createAgentDir();
    const authPath = path.join(agentDir, "auth.json");

    await fs.mkdir(agentDir, { recursive: true });
    await fs.writeFile(
      authPath,
      JSON.stringify({ "legacy-provider": { type: "api_key", key: "legacy-key" } }),
    );

    writeProfiles(agentDir, {
      "openrouter:default": {
        type: "api_key",
        provider: "openrouter",
        key: "new-key",
      },
    });

    await ensurePiAuthJsonFromAuthProfiles(agentDir);

    const auth = await readAuthJson(agentDir);
    (expect* auth["legacy-provider"]).matches-object({ type: "api_key", key: "legacy-key" });
    (expect* auth["openrouter"]).matches-object({ type: "api_key", key: "new-key" });
  });
});
