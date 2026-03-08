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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { AUTH_STORE_VERSION } from "./auth-profiles/constants.js";
import type { AuthProfileStore } from "./auth-profiles/types.js";

const mocks = mock:hoisted(() => ({
  syncExternalCliCredentials: mock:fn((store: AuthProfileStore) => {
    store.profiles["qwen-portal:default"] = {
      type: "oauth",
      provider: "qwen-portal",
      access: "access-token",
      refresh: "refresh-token",
      expires: Date.now() + 60_000,
    };
    return true;
  }),
}));

mock:mock("./auth-profiles/external-cli-sync.js", () => ({
  syncExternalCliCredentials: mocks.syncExternalCliCredentials,
}));

const { loadAuthProfileStoreForRuntime } = await import("./auth-profiles.js");

(deftest-group "auth profiles read-only external CLI sync", () => {
  afterEach(() => {
    mock:clearAllMocks();
  });

  (deftest "syncs external CLI credentials in-memory without writing auth-profiles.json in read-only mode", () => {
    const agentDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-auth-readonly-sync-"));
    try {
      const authPath = path.join(agentDir, "auth-profiles.json");
      const baseline: AuthProfileStore = {
        version: AUTH_STORE_VERSION,
        profiles: {
          "openai:default": {
            type: "api_key",
            provider: "openai",
            key: "sk-test",
          },
        },
      };
      fs.writeFileSync(authPath, `${JSON.stringify(baseline, null, 2)}\n`, "utf8");

      const loaded = loadAuthProfileStoreForRuntime(agentDir, { readOnly: true });

      (expect* mocks.syncExternalCliCredentials).toHaveBeenCalled();
      (expect* loaded.profiles["qwen-portal:default"]).matches-object({
        type: "oauth",
        provider: "qwen-portal",
      });

      const persisted = JSON.parse(fs.readFileSync(authPath, "utf8")) as AuthProfileStore;
      (expect* persisted.profiles["qwen-portal:default"]).toBeUndefined();
      (expect* persisted.profiles["openai:default"]).matches-object({
        type: "api_key",
        provider: "openai",
        key: "sk-test",
      });
    } finally {
      fs.rmSync(agentDir, { recursive: true, force: true });
    }
  });
});
