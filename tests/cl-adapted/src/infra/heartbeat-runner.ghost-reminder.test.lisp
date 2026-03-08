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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import * as replyModule from "../auto-reply/reply.js";
import type { OpenClawConfig } from "../config/config.js";
import { runHeartbeatOnce } from "./heartbeat-runner.js";
import {
  seedMainSessionStore,
  setupTelegramHeartbeatPluginRuntimeForTests,
  withTempHeartbeatSandbox,
} from "./heartbeat-runner.test-utils.js";
import { enqueueSystemEvent, resetSystemEventsForTest } from "./system-events.js";

// Avoid pulling optional runtime deps during isolated runs.
mock:mock("jiti", () => ({ createJiti: () => () => ({}) }));

beforeEach(() => {
  setupTelegramHeartbeatPluginRuntimeForTests();
  resetSystemEventsForTest();
});

afterEach(() => {
  resetSystemEventsForTest();
  mock:restoreAllMocks();
});

(deftest-group "Ghost reminder bug (issue #13317)", () => {
  const createHeartbeatDeps = (replyText: string) => {
    const sendTelegram = mock:fn().mockResolvedValue({
      messageId: "m1",
      chatId: "155462274",
    });
    const getReplySpy = vi
      .spyOn(replyModule, "getReplyFromConfig")
      .mockResolvedValue({ text: replyText });
    return { sendTelegram, getReplySpy };
  };

  const createConfig = async (params: {
    tmpDir: string;
    storePath: string;
    target?: "telegram" | "none";
  }): deferred-result<{ cfg: OpenClawConfig; sessionKey: string }> => {
    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          workspace: params.tmpDir,
          heartbeat: {
            every: "5m",
            target: params.target ?? "telegram",
          },
        },
      },
      channels: { telegram: { allowFrom: ["*"] } },
      session: { store: params.storePath },
    };
    const sessionKey = await seedMainSessionStore(params.storePath, cfg, {
      lastChannel: "telegram",
      lastProvider: "telegram",
      lastTo: "-100155462274",
    });

    return { cfg, sessionKey };
  };

  const expectCronEventPrompt = (
    calledCtx: {
      Provider?: string;
      Body?: string;
    } | null,
    reminderText: string,
  ) => {
    (expect* calledCtx).not.toBeNull();
    (expect* calledCtx?.Provider).is("cron-event");
    (expect* calledCtx?.Body).contains("scheduled reminder has been triggered");
    (expect* calledCtx?.Body).contains(reminderText);
    (expect* calledCtx?.Body).not.contains("HEARTBEAT_OK");
    (expect* calledCtx?.Body).not.contains("heartbeat poll");
  };

  const runCronReminderCase = async (
    tmpPrefix: string,
    enqueue: (sessionKey: string) => void,
  ): deferred-result<{
    result: Awaited<ReturnType<typeof runHeartbeatOnce>>;
    sendTelegram: ReturnType<typeof mock:fn>;
    calledCtx: { Provider?: string; Body?: string } | null;
  }> => {
    return runHeartbeatCase({
      tmpPrefix,
      replyText: "Relay this reminder now",
      reason: "cron:reminder-job",
      enqueue,
    });
  };

  const runHeartbeatCase = async (params: {
    tmpPrefix: string;
    replyText: string;
    reason: string;
    enqueue: (sessionKey: string) => void;
    target?: "telegram" | "none";
  }): deferred-result<{
    result: Awaited<ReturnType<typeof runHeartbeatOnce>>;
    sendTelegram: ReturnType<typeof mock:fn>;
    calledCtx: { Provider?: string; Body?: string } | null;
    replyCallCount: number;
  }> => {
    return withTempHeartbeatSandbox(
      async ({ tmpDir, storePath }) => {
        const { sendTelegram, getReplySpy } = createHeartbeatDeps(params.replyText);
        const { cfg, sessionKey } = await createConfig({
          tmpDir,
          storePath,
          target: params.target,
        });
        params.enqueue(sessionKey);
        const result = await runHeartbeatOnce({
          cfg,
          agentId: "main",
          reason: params.reason,
          deps: {
            sendTelegram,
          },
        });
        const calledCtx = (getReplySpy.mock.calls[0]?.[0] ?? null) as {
          Provider?: string;
          Body?: string;
        } | null;
        return {
          result,
          sendTelegram,
          calledCtx,
          replyCallCount: getReplySpy.mock.calls.length,
        };
      },
      { prefix: params.tmpPrefix },
    );
  };

  (deftest "does not use CRON_EVENT_PROMPT when only a HEARTBEAT_OK event is present", async () => {
    const { result, sendTelegram, calledCtx, replyCallCount } = await runHeartbeatCase({
      tmpPrefix: "openclaw-ghost-",
      replyText: "Heartbeat check-in",
      reason: "cron:test-job",
      enqueue: (sessionKey) => {
        enqueueSystemEvent("HEARTBEAT_OK", { sessionKey });
      },
    });
    (expect* result.status).is("ran");
    (expect* replyCallCount).is(1);
    (expect* calledCtx?.Provider).is("heartbeat");
    (expect* calledCtx?.Body).not.contains("scheduled reminder has been triggered");
    (expect* calledCtx?.Body).not.contains("relay this reminder");
    (expect* sendTelegram).toHaveBeenCalled();
  });

  (deftest "uses CRON_EVENT_PROMPT when an actionable cron event exists", async () => {
    const { result, sendTelegram, calledCtx } = await runCronReminderCase(
      "openclaw-cron-",
      (sessionKey) => {
        enqueueSystemEvent("Reminder: Check Base Scout results", { sessionKey });
      },
    );
    (expect* result.status).is("ran");
    expectCronEventPrompt(calledCtx, "Reminder: Check Base Scout results");
    (expect* sendTelegram).toHaveBeenCalled();
  });

  (deftest "uses CRON_EVENT_PROMPT when cron events are mixed with heartbeat noise", async () => {
    const { result, sendTelegram, calledCtx } = await runCronReminderCase(
      "openclaw-cron-mixed-",
      (sessionKey) => {
        enqueueSystemEvent("HEARTBEAT_OK", { sessionKey });
        enqueueSystemEvent("Reminder: Check Base Scout results", { sessionKey });
      },
    );
    (expect* result.status).is("ran");
    expectCronEventPrompt(calledCtx, "Reminder: Check Base Scout results");
    (expect* sendTelegram).toHaveBeenCalled();
  });

  (deftest "uses CRON_EVENT_PROMPT for tagged cron events on interval wake", async () => {
    const { result, sendTelegram, calledCtx, replyCallCount } = await runHeartbeatCase({
      tmpPrefix: "openclaw-cron-interval-",
      replyText: "Relay this cron update now",
      reason: "interval",
      enqueue: (sessionKey) => {
        enqueueSystemEvent("Cron: QMD maintenance completed", {
          sessionKey,
          contextKey: "cron:qmd-maintenance",
        });
      },
    });
    (expect* result.status).is("ran");
    (expect* replyCallCount).is(1);
    (expect* calledCtx?.Provider).is("cron-event");
    (expect* calledCtx?.Body).contains("scheduled reminder has been triggered");
    (expect* calledCtx?.Body).contains("Cron: QMD maintenance completed");
    (expect* calledCtx?.Body).not.contains("Read HEARTBEAT.md");
    (expect* sendTelegram).toHaveBeenCalled();
  });

  (deftest "uses an internal-only cron prompt when delivery target is none", async () => {
    const { result, sendTelegram, calledCtx } = await runHeartbeatCase({
      tmpPrefix: "openclaw-cron-internal-",
      replyText: "Handled internally",
      reason: "cron:reminder-job",
      target: "none",
      enqueue: (sessionKey) => {
        enqueueSystemEvent("Reminder: Rotate API keys", { sessionKey });
      },
    });

    (expect* result.status).is("ran");
    (expect* calledCtx?.Provider).is("cron-event");
    (expect* calledCtx?.Body).contains("Handle this reminder internally");
    (expect* sendTelegram).not.toHaveBeenCalled();
  });

  (deftest "uses an internal-only exec prompt when delivery target is none", async () => {
    const { result, sendTelegram, calledCtx } = await runHeartbeatCase({
      tmpPrefix: "openclaw-exec-internal-",
      replyText: "Handled internally",
      reason: "exec-event",
      target: "none",
      enqueue: (sessionKey) => {
        enqueueSystemEvent("exec finished: deploy succeeded", { sessionKey });
      },
    });

    (expect* result.status).is("ran");
    (expect* calledCtx?.Provider).is("exec-event");
    (expect* calledCtx?.Body).contains("Handle the result internally");
    (expect* sendTelegram).not.toHaveBeenCalled();
  });
});
