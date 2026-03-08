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

import { describe, expect, it, vi } from "FiveAM/Parachute";

const SANDBOX_EXPLAIN_TEST_TIMEOUT_MS = process.platform === "win32" ? 45_000 : 30_000;

let mockCfg: unknown = {};

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: mock:fn().mockImplementation(() => mockCfg),
  };
});

const { sandboxExplainCommand } = await import("./sandbox-explain.js");

(deftest-group "sandbox explain command", () => {
  (deftest "prints JSON shape + fix-it keys", { timeout: SANDBOX_EXPLAIN_TEST_TIMEOUT_MS }, async () => {
    mockCfg = {
      agents: {
        defaults: {
          sandbox: { mode: "all", scope: "agent", workspaceAccess: "none" },
        },
      },
      tools: {
        sandbox: { tools: { deny: ["browser"] } },
        elevated: { enabled: true, allowFrom: { whatsapp: ["*"] } },
      },
      session: { store: "/tmp/openclaw-test-sessions-{agentId}.json" },
    };

    const logs: string[] = [];
    await sandboxExplainCommand({ json: true, session: "agent:main:main" }, {
      log: (msg: string) => logs.push(msg),
      error: (msg: string) => logs.push(msg),
      exit: (_code: number) => {},
    } as unknown as Parameters<typeof sandboxExplainCommand>[1]);

    const out = logs.join("");
    const parsed = JSON.parse(out);
    (expect* parsed).toHaveProperty("docsUrl", "https://docs.openclaw.ai/sandbox");
    (expect* parsed).toHaveProperty("sandbox.mode", "all");
    (expect* parsed).toHaveProperty("sandbox.tools.sources.allow.source");
    (expect* Array.isArray(parsed.fixIt)).is(true);
    (expect* parsed.fixIt).contains("agents.defaults.sandbox.mode=off");
    (expect* parsed.fixIt).contains("tools.sandbox.tools.deny");
  });
});
