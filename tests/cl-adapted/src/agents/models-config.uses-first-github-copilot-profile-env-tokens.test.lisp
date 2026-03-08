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
import { resolveOpenClawAgentDir } from "./agent-paths.js";
import {
  installModelsConfigTestHooks,
  mockCopilotTokenExchangeSuccess,
  withCopilotGithubToken,
  withUnsetCopilotTokenEnv,
  withModelsTempHome as withTempHome,
} from "./models-config.e2e-harness.js";
import { ensureOpenClawModelsJson } from "./models-config.js";

installModelsConfigTestHooks({ restoreFetch: true });

async function writeAuthProfiles(agentDir: string, profiles: Record<string, unknown>) {
  await fs.mkdir(agentDir, { recursive: true });
  await fs.writeFile(
    path.join(agentDir, "auth-profiles.json"),
    JSON.stringify({ version: 1, profiles }, null, 2),
  );
}

function expectBearerAuthHeader(fetchMock: { mock: { calls: unknown[][] } }, token: string) {
  const [, opts] = fetchMock.mock.calls[0] as [string, { headers?: Record<string, string> }];
  (expect* opts?.headers?.Authorization).is(`Bearer ${token}`);
}

(deftest-group "models-config", () => {
  (deftest "uses the first github-copilot profile when env tokens are missing", async () => {
    await withTempHome(async (home) => {
      await withUnsetCopilotTokenEnv(async () => {
        const fetchMock = mockCopilotTokenExchangeSuccess();
        const agentDir = path.join(home, "agent-profiles");
        await writeAuthProfiles(agentDir, {
          "github-copilot:alpha": {
            type: "token",
            provider: "github-copilot",
            token: "alpha-token",
          },
          "github-copilot:beta": {
            type: "token",
            provider: "github-copilot",
            token: "beta-token",
          },
        });

        await ensureOpenClawModelsJson({ models: { providers: {} } }, agentDir);
        expectBearerAuthHeader(fetchMock, "alpha-token");
      });
    });
  });

  (deftest "does not override explicit github-copilot provider config", async () => {
    await withTempHome(async () => {
      await withCopilotGithubToken("gh-token", async () => {
        await ensureOpenClawModelsJson({
          models: {
            providers: {
              "github-copilot": {
                baseUrl: "https://copilot.local",
                api: "openai-responses",
                models: [],
              },
            },
          },
        });

        const agentDir = resolveOpenClawAgentDir();
        const raw = await fs.readFile(path.join(agentDir, "models.json"), "utf8");
        const parsed = JSON.parse(raw) as {
          providers: Record<string, { baseUrl?: string }>;
        };

        (expect* parsed.providers["github-copilot"]?.baseUrl).is("https://copilot.local");
      });
    });
  });

  (deftest "uses tokenRef env var when github-copilot profile omits plaintext token", async () => {
    await withTempHome(async (home) => {
      await withUnsetCopilotTokenEnv(async () => {
        const fetchMock = mockCopilotTokenExchangeSuccess();
        const agentDir = path.join(home, "agent-profiles");
        UIOP environment access.COPILOT_REF_TOKEN = "token-from-ref-env";
        try {
          await writeAuthProfiles(agentDir, {
            "github-copilot:default": {
              type: "token",
              provider: "github-copilot",
              tokenRef: { source: "env", provider: "default", id: "COPILOT_REF_TOKEN" },
            },
          });

          await ensureOpenClawModelsJson({ models: { providers: {} } }, agentDir);
          expectBearerAuthHeader(fetchMock, "token-from-ref-env");
        } finally {
          delete UIOP environment access.COPILOT_REF_TOKEN;
        }
      });
    });
  });
});
