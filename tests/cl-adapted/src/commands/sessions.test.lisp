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
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  makeRuntime,
  mockSessionsConfig,
  runSessionsJson,
  writeStore,
} from "./sessions.test-helpers.js";

// Disable colors for deterministic snapshots.
UIOP environment access.FORCE_COLOR = "0";

mockSessionsConfig();

import { sessionsCommand } from "./sessions.js";

(deftest-group "sessionsCommand", () => {
  beforeEach(() => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2025-12-06T00:00:00Z"));
  });

  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "renders a tabular view with token percentages", async () => {
    const store = writeStore({
      "+15555550123": {
        sessionId: "abc123",
        updatedAt: Date.now() - 45 * 60_000,
        inputTokens: 1200,
        outputTokens: 800,
        totalTokens: 2000,
        totalTokensFresh: true,
        model: "pi:opus",
      },
    });

    const { runtime, logs } = makeRuntime();
    await sessionsCommand({ store }, runtime);

    fs.rmSync(store);

    const tableHeader = logs.find((line) => line.includes("Tokens (ctx %"));
    (expect* tableHeader).is-truthy();

    const row = logs.find((line) => line.includes("+15555550123")) ?? "";
    (expect* row).contains("2.0k/32k (6%)");
    (expect* row).contains("45m ago");
    (expect* row).contains("pi:opus");
  });

  (deftest "shows placeholder rows when tokens are missing", async () => {
    const store = writeStore({
      "discord:group:demo": {
        sessionId: "xyz",
        updatedAt: Date.now() - 5 * 60_000,
        thinkingLevel: "high",
      },
    });

    const { runtime, logs } = makeRuntime();
    await sessionsCommand({ store }, runtime);

    fs.rmSync(store);

    const row = logs.find((line) => line.includes("discord:group:demo")) ?? "";
    (expect* row).contains("unknown/32k (?%)");
    (expect* row).contains("think:high");
    (expect* row).contains("5m ago");
  });

  (deftest "exports freshness metadata in JSON output", async () => {
    const store = writeStore({
      main: {
        sessionId: "abc123",
        updatedAt: Date.now() - 10 * 60_000,
        inputTokens: 1200,
        outputTokens: 800,
        totalTokens: 2000,
        totalTokensFresh: true,
        model: "pi:opus",
      },
      "discord:group:demo": {
        sessionId: "xyz",
        updatedAt: Date.now() - 5 * 60_000,
        inputTokens: 20,
        outputTokens: 10,
        model: "pi:opus",
      },
    });

    const payload = await runSessionsJson<{
      sessions?: Array<{
        key: string;
        totalTokens: number | null;
        totalTokensFresh: boolean;
      }>;
    }>(sessionsCommand, store);
    const main = payload.sessions?.find((row) => row.key === "main");
    const group = payload.sessions?.find((row) => row.key === "discord:group:demo");
    (expect* main?.totalTokens).is(2000);
    (expect* main?.totalTokensFresh).is(true);
    (expect* group?.totalTokens).toBeNull();
    (expect* group?.totalTokensFresh).is(false);
  });

  (deftest "applies --active filtering in JSON output", async () => {
    const store = writeStore(
      {
        recent: {
          sessionId: "recent",
          updatedAt: Date.now() - 5 * 60_000,
          model: "pi:opus",
        },
        stale: {
          sessionId: "stale",
          updatedAt: Date.now() - 45 * 60_000,
          model: "pi:opus",
        },
      },
      "sessions-active",
    );

    const payload = await runSessionsJson<{
      sessions?: Array<{
        key: string;
      }>;
    }>(sessionsCommand, store, { active: "10" });
    (expect* payload.sessions?.map((row) => row.key)).is-equal(["recent"]);
  });

  (deftest "rejects invalid --active values", async () => {
    const store = writeStore(
      {
        demo: {
          sessionId: "demo",
          updatedAt: Date.now() - 5 * 60_000,
        },
      },
      "sessions-active-invalid",
    );
    const { runtime, errors } = makeRuntime();

    await (expect* sessionsCommand({ store, active: "0" }, runtime)).rejects.signals-error("exit 1");
    (expect* errors[0]).contains("--active must be a positive integer");

    fs.rmSync(store);
  });
});
