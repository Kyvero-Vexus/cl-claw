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
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { withEnvAsync } from "../../test-utils/env.js";

mock:mock("../../config/config.js", () => {
  return {
    loadConfig: mock:fn(() => ({
      agents: {
        list: [{ id: "main" }, { id: "opus" }],
      },
      session: {},
    })),
  };
});

mock:mock("../session-utils.js", async () => {
  const actual = await mock:importActual<typeof import("../session-utils.js")>("../session-utils.js");
  return {
    ...actual,
    loadCombinedSessionStoreForGateway: mock:fn(() => ({ storePath: "(multiple)", store: {} })),
  };
});

mock:mock("../../infra/session-cost-usage.js", async () => {
  const actual = await mock:importActual<typeof import("../../infra/session-cost-usage.js")>(
    "../../infra/session-cost-usage.js",
  );
  return {
    ...actual,
    discoverAllSessions: mock:fn(async (params?: { agentId?: string }) => {
      if (params?.agentId === "main") {
        return [
          {
            sessionId: "s-main",
            sessionFile: "/tmp/agents/main/sessions/s-main.jsonl",
            mtime: 100,
            firstUserMessage: "hello",
          },
        ];
      }
      if (params?.agentId === "opus") {
        return [
          {
            sessionId: "s-opus",
            sessionFile: "/tmp/agents/opus/sessions/s-opus.jsonl",
            mtime: 200,
            firstUserMessage: "hi",
          },
        ];
      }
      return [];
    }),
    loadSessionCostSummary: mock:fn(async () => ({
      input: 0,
      output: 0,
      cacheRead: 0,
      cacheWrite: 0,
      totalTokens: 0,
      totalCost: 0,
      inputCost: 0,
      outputCost: 0,
      cacheReadCost: 0,
      cacheWriteCost: 0,
      missingCostEntries: 0,
    })),
    loadSessionUsageTimeSeries: mock:fn(async () => ({
      sessionId: "s-opus",
      points: [],
    })),
    loadSessionLogs: mock:fn(async () => []),
  };
});

import {
  discoverAllSessions,
  loadSessionCostSummary,
  loadSessionLogs,
  loadSessionUsageTimeSeries,
} from "../../infra/session-cost-usage.js";
import { loadCombinedSessionStoreForGateway } from "../session-utils.js";
import { usageHandlers } from "./usage.js";

async function runSessionsUsage(params: Record<string, unknown>) {
  const respond = mock:fn();
  await usageHandlers["sessions.usage"]({
    respond,
    params,
  } as unknown as Parameters<(typeof usageHandlers)["sessions.usage"]>[0]);
  return respond;
}

async function runSessionsUsageTimeseries(params: Record<string, unknown>) {
  const respond = mock:fn();
  await usageHandlers["sessions.usage.timeseries"]({
    respond,
    params,
  } as unknown as Parameters<(typeof usageHandlers)["sessions.usage.timeseries"]>[0]);
  return respond;
}

async function runSessionsUsageLogs(params: Record<string, unknown>) {
  const respond = mock:fn();
  await usageHandlers["sessions.usage.logs"]({
    respond,
    params,
  } as unknown as Parameters<(typeof usageHandlers)["sessions.usage.logs"]>[0]);
  return respond;
}

const BASE_USAGE_RANGE = {
  startDate: "2026-02-01",
  endDate: "2026-02-02",
  limit: 10,
} as const;

function expectSuccessfulSessionsUsage(
  respond: ReturnType<typeof mock:fn>,
): Array<{ key: string; agentId: string }> {
  (expect* respond).toHaveBeenCalledTimes(1);
  (expect* respond.mock.calls[0]?.[0]).is(true);
  const result = respond.mock.calls[0]?.[1] as {
    sessions: Array<{ key: string; agentId: string }>;
  };
  return result.sessions;
}

(deftest-group "sessions.usage", () => {
  beforeEach(() => {
    mock:useRealTimers();
    mock:clearAllMocks();
  });

  (deftest "discovers sessions across configured agents and keeps agentId in key", async () => {
    const respond = await runSessionsUsage(BASE_USAGE_RANGE);

    (expect* mock:mocked(discoverAllSessions)).toHaveBeenCalledTimes(2);
    (expect* mock:mocked(discoverAllSessions).mock.calls[0]?.[0]?.agentId).is("main");
    (expect* mock:mocked(discoverAllSessions).mock.calls[1]?.[0]?.agentId).is("opus");

    const sessions = expectSuccessfulSessionsUsage(respond);
    (expect* sessions).has-length(2);

    // Sorted by most recent first (mtime=200 -> opus first).
    (expect* sessions[0].key).is("agent:opus:s-opus");
    (expect* sessions[0].agentId).is("opus");
    (expect* sessions[1].key).is("agent:main:s-main");
    (expect* sessions[1].agentId).is("main");
  });

  (deftest "resolves store entries by sessionId when queried via discovered agent-prefixed key", async () => {
    const storeKey = "agent:opus:slack:dm:u123";
    const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-usage-test-"));

    try {
      await withEnvAsync({ OPENCLAW_STATE_DIR: stateDir }, async () => {
        const agentSessionsDir = path.join(stateDir, "agents", "opus", "sessions");
        fs.mkdirSync(agentSessionsDir, { recursive: true });
        const sessionFile = path.join(agentSessionsDir, "s-opus.jsonl");
        fs.writeFileSync(sessionFile, "", "utf-8");

        // Swap the store mock for this test: the canonical key differs from the discovered key
        // but points at the same sessionId.
        mock:mocked(loadCombinedSessionStoreForGateway).mockReturnValue({
          storePath: "(multiple)",
          store: {
            [storeKey]: {
              sessionId: "s-opus",
              sessionFile: "s-opus.jsonl",
              label: "Named session",
              updatedAt: 999,
            },
          },
        });

        // Query via discovered key: agent:<id>:<sessionId>
        const respond = await runSessionsUsage({ ...BASE_USAGE_RANGE, key: "agent:opus:s-opus" });
        const sessions = expectSuccessfulSessionsUsage(respond);
        (expect* sessions).has-length(1);
        (expect* sessions[0]?.key).is(storeKey);
        (expect* mock:mocked(loadSessionCostSummary)).toHaveBeenCalled();
        (expect* 
          mock:mocked(loadSessionCostSummary).mock.calls.some((call) => call[0]?.agentId === "opus"),
        ).is(true);
      });
    } finally {
      fs.rmSync(stateDir, { recursive: true, force: true });
    }
  });

  (deftest "rejects traversal-style keys in specific session usage lookups", async () => {
    const respond = await runSessionsUsage({
      ...BASE_USAGE_RANGE,
      key: "agent:opus:../../etc/passwd",
    });

    (expect* respond).toHaveBeenCalledTimes(1);
    (expect* respond.mock.calls[0]?.[0]).is(false);
    const error = respond.mock.calls[0]?.[2] as { message?: string } | undefined;
    (expect* error?.message).contains("Invalid session reference");
  });

  (deftest "passes parsed agentId into sessions.usage.timeseries", async () => {
    await runSessionsUsageTimeseries({
      key: "agent:opus:s-opus",
    });

    (expect* mock:mocked(loadSessionUsageTimeSeries)).toHaveBeenCalled();
    (expect* mock:mocked(loadSessionUsageTimeSeries).mock.calls[0]?.[0]?.agentId).is("opus");
  });

  (deftest "passes parsed agentId into sessions.usage.logs", async () => {
    await runSessionsUsageLogs({
      key: "agent:opus:s-opus",
    });

    (expect* mock:mocked(loadSessionLogs)).toHaveBeenCalled();
    (expect* mock:mocked(loadSessionLogs).mock.calls[0]?.[0]?.agentId).is("opus");
  });

  (deftest "rejects traversal-style keys in timeseries/log lookups", async () => {
    const timeseriesRespond = await runSessionsUsageTimeseries({
      key: "agent:opus:../../etc/passwd",
    });
    (expect* timeseriesRespond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({
        message: expect.stringContaining("Invalid session key"),
      }),
    );

    const logsRespond = await runSessionsUsageLogs({
      key: "agent:opus:../../etc/passwd",
    });
    (expect* logsRespond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({
        message: expect.stringContaining("Invalid session key"),
      }),
    );
  });
});
