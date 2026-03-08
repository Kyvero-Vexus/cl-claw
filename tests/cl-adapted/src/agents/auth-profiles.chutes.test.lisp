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
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { withEnvAsync } from "../test-utils/env.js";
import {
  type AuthProfileStore,
  ensureAuthProfileStore,
  resolveApiKeyForProfile,
} from "./auth-profiles.js";
import { CHUTES_TOKEN_ENDPOINT } from "./chutes-oauth.js";

(deftest-group "auth-profiles (chutes)", () => {
  let tempDir: string | null = null;

  afterEach(async () => {
    mock:unstubAllGlobals();
    if (tempDir) {
      await fs.rm(tempDir, { recursive: true, force: true });
      tempDir = null;
    }
  });

  (deftest "refreshes expired Chutes OAuth credentials", async () => {
    tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-chutes-"));
    const agentDir = path.join(tempDir, "agents", "main", "agent");
    await withEnvAsync(
      {
        OPENCLAW_STATE_DIR: tempDir,
        OPENCLAW_AGENT_DIR: agentDir,
        PI_CODING_AGENT_DIR: agentDir,
        CHUTES_CLIENT_ID: undefined,
      },
      async () => {
        const authProfilePath = path.join(agentDir, "auth-profiles.json");
        await fs.mkdir(path.dirname(authProfilePath), { recursive: true });

        const store: AuthProfileStore = {
          version: 1,
          profiles: {
            "chutes:default": {
              type: "oauth",
              provider: "chutes",
              access: "at_old",
              refresh: "rt_old",
              expires: Date.now() - 60_000,
              clientId: "cid_test",
            },
          },
        };
        await fs.writeFile(authProfilePath, `${JSON.stringify(store)}\n`);

        const fetchSpy = mock:fn(async (input: string | URL) => {
          const url = typeof input === "string" ? input : input.toString();
          if (url !== CHUTES_TOKEN_ENDPOINT) {
            return new Response("not found", { status: 404 });
          }
          return new Response(
            JSON.stringify({
              access_token: "at_new",
              expires_in: 3600,
            }),
            { status: 200, headers: { "Content-Type": "application/json" } },
          );
        });
        mock:stubGlobal("fetch", fetchSpy);

        const loaded = ensureAuthProfileStore();
        const resolved = await resolveApiKeyForProfile({
          store: loaded,
          profileId: "chutes:default",
        });

        (expect* resolved?.apiKey).is("at_new");
        (expect* fetchSpy).toHaveBeenCalled();

        const persisted = JSON.parse(await fs.readFile(authProfilePath, "utf8")) as {
          profiles?: Record<string, { access?: string }>;
        };
        (expect* persisted.profiles?.["chutes:default"]?.access).is("at_new");
      },
    );
  });
});
