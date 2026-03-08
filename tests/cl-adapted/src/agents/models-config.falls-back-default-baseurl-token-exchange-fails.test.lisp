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
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { DEFAULT_COPILOT_API_BASE_URL } from "../providers/github-copilot-token.js";
import { withEnvAsync } from "../test-utils/env.js";
import {
  installModelsConfigTestHooks,
  mockCopilotTokenExchangeSuccess,
  withUnsetCopilotTokenEnv,
  withModelsTempHome as withTempHome,
} from "./models-config.e2e-harness.js";
import { ensureOpenClawModelsJson } from "./models-config.js";

installModelsConfigTestHooks({ restoreFetch: true });

async function readCopilotBaseUrl(agentDir: string) {
  const raw = await fs.readFile(path.join(agentDir, "models.json"), "utf8");
  const parsed = JSON.parse(raw) as {
    providers: Record<string, { baseUrl?: string }>;
  };
  return parsed.providers["github-copilot"]?.baseUrl;
}

(deftest-group "models-config", () => {
  (deftest "falls back to default baseUrl when token exchange fails", async () => {
    await withTempHome(async () => {
      await withEnvAsync({ COPILOT_GITHUB_TOKEN: "gh-token" }, async () => {
        const fetchMock = mock:fn().mockResolvedValue({
          ok: false,
          status: 500,
          json: async () => ({ message: "boom" }),
        });
        globalThis.fetch = fetchMock as unknown as typeof fetch;

        const { agentDir } = await ensureOpenClawModelsJson({ models: { providers: {} } });
        (expect* await readCopilotBaseUrl(agentDir)).is(DEFAULT_COPILOT_API_BASE_URL);
      });
    });
  });

  (deftest "uses agentDir override auth profiles for copilot injection", async () => {
    await withTempHome(async (home) => {
      await withUnsetCopilotTokenEnv(async () => {
        mockCopilotTokenExchangeSuccess();
        const agentDir = path.join(home, "agent-override");
        await fs.mkdir(agentDir, { recursive: true });
        await fs.writeFile(
          path.join(agentDir, "auth-profiles.json"),
          JSON.stringify(
            {
              version: 1,
              profiles: {
                "github-copilot:github": {
                  type: "token",
                  provider: "github-copilot",
                  token: "gh-profile-token",
                },
              },
            },
            null,
            2,
          ),
        );

        await ensureOpenClawModelsJson({ models: { providers: {} } }, agentDir);

        (expect* await readCopilotBaseUrl(agentDir)).is("https://api.copilot.example");
      });
    });
  });
});
