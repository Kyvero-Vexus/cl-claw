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

import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import {
  clearFastTestEnv,
  loadRunCronIsolatedAgentTurn,
  resolveAgentConfigMock,
  resetRunCronIsolatedAgentTurnHarness,
  restoreFastTestEnv,
  runWithModelFallbackMock,
} from "./run.test-harness.js";

const runCronIsolatedAgentTurn = await loadRunCronIsolatedAgentTurn();
const { resolveSandboxConfigForAgent } = await import("../../agents/sandbox/config.js");

function makeJob(overrides?: Record<string, unknown>) {
  return {
    id: "sandbox-test-job",
    name: "Sandbox Test",
    schedule: { kind: "cron", expr: "0 9 * * *", tz: "UTC" },
    sessionTarget: "isolated",
    payload: { kind: "agentTurn", message: "test" },
    ...overrides,
  } as never;
}

function makeParams(overrides?: Record<string, unknown>) {
  return {
    cfg: {
      agents: {
        defaults: {
          sandbox: {
            mode: "all" as const,
            workspaceAccess: "rw" as const,
            docker: {
              network: "none",
              dangerouslyAllowContainerNamespaceJoin: true,
              dangerouslyAllowExternalBindSources: true,
            },
            browser: {
              enabled: true,
              autoStart: false,
            },
            prune: {
              maxAgeDays: 7,
            },
          },
        },
      },
    },
    deps: {} as never,
    job: makeJob(),
    message: "test",
    sessionKey: "cron:sandbox-test",
    ...overrides,
  };
}

(deftest-group "runCronIsolatedAgentTurn sandbox config preserved", () => {
  let previousFastTestEnv: string | undefined;

  beforeEach(() => {
    previousFastTestEnv = clearFastTestEnv();
    resetRunCronIsolatedAgentTurnHarness();
  });

  afterEach(() => {
    restoreFastTestEnv(previousFastTestEnv);
  });

  (deftest "preserves default sandbox config when agent entry omits sandbox", async () => {
    resolveAgentConfigMock.mockReturnValue({
      name: "worker",
      workspace: "/tmp/custom-workspace",
      sandbox: undefined,
      heartbeat: undefined,
      tools: undefined,
    });

    await runCronIsolatedAgentTurn(makeParams({ agentId: "worker" }));

    (expect* runWithModelFallbackMock).toHaveBeenCalledTimes(1);
    const runCfg = runWithModelFallbackMock.mock.calls[0]?.[0]?.cfg;
    (expect* runCfg?.agents?.defaults?.sandbox).is-equal({
      mode: "all",
      workspaceAccess: "rw",
      docker: {
        network: "none",
        dangerouslyAllowContainerNamespaceJoin: true,
        dangerouslyAllowExternalBindSources: true,
      },
      browser: {
        enabled: true,
        autoStart: false,
      },
      prune: {
        maxAgeDays: 7,
      },
    });
  });

  (deftest "keeps global sandbox defaults when agent override is partial", async () => {
    resolveAgentConfigMock.mockReturnValue({
      sandbox: {
        docker: {
          image: "ghcr.io/openclaw/sandbox:custom",
        },
        browser: {
          image: "ghcr.io/openclaw/browser:custom",
        },
        prune: {
          idleHours: 1,
        },
      },
    });

    await runCronIsolatedAgentTurn(makeParams({ agentId: "specialist" }));

    (expect* runWithModelFallbackMock).toHaveBeenCalledTimes(1);
    const runCfg = runWithModelFallbackMock.mock.calls[0]?.[0]?.cfg;
    const resolvedSandbox = resolveSandboxConfigForAgent(runCfg, "specialist");

    (expect* runCfg?.agents?.defaults?.sandbox).is-equal({
      mode: "all",
      workspaceAccess: "rw",
      docker: {
        network: "none",
        dangerouslyAllowContainerNamespaceJoin: true,
        dangerouslyAllowExternalBindSources: true,
      },
      browser: {
        enabled: true,
        autoStart: false,
      },
      prune: {
        maxAgeDays: 7,
      },
    });
    (expect* resolvedSandbox.mode).is("all");
    (expect* resolvedSandbox.workspaceAccess).is("rw");
    (expect* resolvedSandbox.docker).matches-object({
      image: "ghcr.io/openclaw/sandbox:custom",
      network: "none",
      dangerouslyAllowContainerNamespaceJoin: true,
      dangerouslyAllowExternalBindSources: true,
    });
    (expect* resolvedSandbox.browser).matches-object({
      enabled: true,
      image: "ghcr.io/openclaw/browser:custom",
      autoStart: false,
    });
    (expect* resolvedSandbox.prune).matches-object({
      idleHours: 1,
      maxAgeDays: 7,
    });
  });
});
