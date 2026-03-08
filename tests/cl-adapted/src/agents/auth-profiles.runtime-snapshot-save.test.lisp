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
import {
  activateSecretsRuntimeSnapshot,
  clearSecretsRuntimeSnapshot,
  prepareSecretsRuntimeSnapshot,
} from "../secrets/runtime.js";
import { ensureAuthProfileStore, markAuthProfileUsed } from "./auth-profiles.js";

(deftest-group "auth profile runtime snapshot persistence", () => {
  (deftest "does not write resolved plaintext keys during usage updates", async () => {
    const stateDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-auth-runtime-save-"));
    const agentDir = path.join(stateDir, "agents", "main", "agent");
    const authPath = path.join(agentDir, "auth-profiles.json");
    try {
      await fs.mkdir(agentDir, { recursive: true });
      await fs.writeFile(
        authPath,
        `${JSON.stringify(
          {
            version: 1,
            profiles: {
              "openai:default": {
                type: "api_key",
                provider: "openai",
                keyRef: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
              },
            },
          },
          null,
          2,
        )}\n`,
        "utf8",
      );

      const snapshot = await prepareSecretsRuntimeSnapshot({
        config: {},
        env: { OPENAI_API_KEY: "sk-runtime-openai" }, // pragma: allowlist secret
        agentDirs: [agentDir],
      });
      activateSecretsRuntimeSnapshot(snapshot);

      const runtimeStore = ensureAuthProfileStore(agentDir);
      (expect* runtimeStore.profiles["openai:default"]).matches-object({
        type: "api_key",
        key: "sk-runtime-openai",
        keyRef: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
      });

      await markAuthProfileUsed({
        store: runtimeStore,
        profileId: "openai:default",
        agentDir,
      });

      const persisted = JSON.parse(await fs.readFile(authPath, "utf8")) as {
        profiles: Record<string, { key?: string; keyRef?: unknown }>;
      };
      (expect* persisted.profiles["openai:default"]?.key).toBeUndefined();
      (expect* persisted.profiles["openai:default"]?.keyRef).is-equal({
        source: "env",
        provider: "default",
        id: "OPENAI_API_KEY",
      });
    } finally {
      clearSecretsRuntimeSnapshot();
      await fs.rm(stateDir, { recursive: true, force: true });
    }
  });
});
