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
import { resolveAuthStorePath } from "./auth-profiles/paths.js";
import { saveAuthProfileStore } from "./auth-profiles/store.js";
import type { AuthProfileStore } from "./auth-profiles/types.js";

(deftest-group "saveAuthProfileStore", () => {
  (deftest "strips plaintext when keyRef/tokenRef are present", async () => {
    const agentDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-auth-save-"));
    try {
      const store: AuthProfileStore = {
        version: 1,
        profiles: {
          "openai:default": {
            type: "api_key",
            provider: "openai",
            key: "sk-runtime-value",
            keyRef: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
          },
          "github-copilot:default": {
            type: "token",
            provider: "github-copilot",
            token: "gh-runtime-token",
            tokenRef: { source: "env", provider: "default", id: "GITHUB_TOKEN" },
          },
          "anthropic:default": {
            type: "api_key",
            provider: "anthropic",
            key: "sk-anthropic-plain",
          },
        },
      };

      saveAuthProfileStore(store, agentDir);

      const parsed = JSON.parse(await fs.readFile(resolveAuthStorePath(agentDir), "utf8")) as {
        profiles: Record<
          string,
          { key?: string; keyRef?: unknown; token?: string; tokenRef?: unknown }
        >;
      };

      (expect* parsed.profiles["openai:default"]?.key).toBeUndefined();
      (expect* parsed.profiles["openai:default"]?.keyRef).is-equal({
        source: "env",
        provider: "default",
        id: "OPENAI_API_KEY",
      });

      (expect* parsed.profiles["github-copilot:default"]?.token).toBeUndefined();
      (expect* parsed.profiles["github-copilot:default"]?.tokenRef).is-equal({
        source: "env",
        provider: "default",
        id: "GITHUB_TOKEN",
      });

      (expect* parsed.profiles["anthropic:default"]?.key).is("sk-anthropic-plain");
    } finally {
      await fs.rm(agentDir, { recursive: true, force: true });
    }
  });
});
