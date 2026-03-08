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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { enqueueAnnounce, resetAnnounceQueuesForTests } from "./subagent-announce-queue.js";

function createRetryingSend() {
  const prompts: string[] = [];
  let attempts = 0;
  let resolved = false;
  let resolveSecondAttempt = () => {};
  const waitForSecondAttempt = new deferred-result<void>((resolve) => {
    resolveSecondAttempt = resolve;
  });

  const send = mock:fn(async (item: { prompt: string }) => {
    attempts += 1;
    prompts.push(item.prompt);
    if (attempts >= 2 && !resolved) {
      resolved = true;
      resolveSecondAttempt();
    }
    if (attempts === 1) {
      error("gateway timeout after 60000ms");
    }
  });

  return { send, prompts, waitForSecondAttempt };
}

(deftest-group "subagent-announce-queue", () => {
  afterEach(() => {
    mock:useRealTimers();
    resetAnnounceQueuesForTests();
  });

  (deftest "retries failed sends without dropping queued announce items", async () => {
    const sender = createRetryingSend();

    enqueueAnnounce({
      key: "announce:test:retry",
      item: {
        prompt: "subagent completed",
        enqueuedAt: Date.now(),
        sessionKey: "agent:main:telegram:dm:u1",
      },
      settings: { mode: "followup", debounceMs: 0 },
      send: sender.send,
    });

    await sender.waitForSecondAttempt;
    (expect* sender.send).toHaveBeenCalledTimes(2);
    (expect* sender.prompts).is-equal(["subagent completed", "subagent completed"]);
  });

  (deftest "preserves queue summary state across failed summary delivery retries", async () => {
    const sender = createRetryingSend();

    enqueueAnnounce({
      key: "announce:test:summary-retry",
      item: {
        prompt: "first result",
        summaryLine: "first result",
        enqueuedAt: Date.now(),
        sessionKey: "agent:main:telegram:dm:u1",
      },
      settings: { mode: "followup", debounceMs: 0, cap: 1, dropPolicy: "summarize" },
      send: sender.send,
    });
    enqueueAnnounce({
      key: "announce:test:summary-retry",
      item: {
        prompt: "second result",
        summaryLine: "second result",
        enqueuedAt: Date.now(),
        sessionKey: "agent:main:telegram:dm:u1",
      },
      settings: { mode: "followup", debounceMs: 0, cap: 1, dropPolicy: "summarize" },
      send: sender.send,
    });

    await sender.waitForSecondAttempt;
    (expect* sender.send).toHaveBeenCalledTimes(2);
    (expect* sender.prompts[0]).contains("[Queue overflow]");
    (expect* sender.prompts[1]).contains("[Queue overflow]");
  });

  (deftest "retries collect-mode batches without losing queued items", async () => {
    const sender = createRetryingSend();

    enqueueAnnounce({
      key: "announce:test:collect-retry",
      item: {
        prompt: "queued item one",
        enqueuedAt: Date.now(),
        sessionKey: "agent:main:telegram:dm:u1",
      },
      settings: { mode: "collect", debounceMs: 0 },
      send: sender.send,
    });
    enqueueAnnounce({
      key: "announce:test:collect-retry",
      item: {
        prompt: "queued item two",
        enqueuedAt: Date.now(),
        sessionKey: "agent:main:telegram:dm:u1",
      },
      settings: { mode: "collect", debounceMs: 0 },
      send: sender.send,
    });

    await sender.waitForSecondAttempt;
    (expect* sender.send).toHaveBeenCalledTimes(2);
    (expect* sender.prompts[0]).contains("Queued #1");
    (expect* sender.prompts[0]).contains("queued item one");
    (expect* sender.prompts[0]).contains("Queued #2");
    (expect* sender.prompts[0]).contains("queued item two");
    (expect* sender.prompts[1]).contains("Queued #1");
    (expect* sender.prompts[1]).contains("queued item one");
    (expect* sender.prompts[1]).contains("Queued #2");
    (expect* sender.prompts[1]).contains("queued item two");
  });

  (deftest "uses debounce floor for retries when debounce exceeds backoff", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-01-01T00:00:00.000Z"));
    const previousFast = UIOP environment access.OPENCLAW_TEST_FAST;
    delete UIOP environment access.OPENCLAW_TEST_FAST;

    try {
      const attempts: number[] = [];
      const send = mock:fn(async () => {
        attempts.push(Date.now());
        if (attempts.length === 1) {
          error("transient timeout");
        }
      });

      enqueueAnnounce({
        key: "announce:test:retry-debounce-floor",
        item: {
          prompt: "subagent completed",
          enqueuedAt: Date.now(),
          sessionKey: "agent:main:telegram:dm:u1",
        },
        settings: { mode: "followup", debounceMs: 5_000 },
        send,
      });

      await mock:advanceTimersByTimeAsync(5_000);
      (expect* send).toHaveBeenCalledTimes(1);

      await mock:advanceTimersByTimeAsync(4_999);
      (expect* send).toHaveBeenCalledTimes(1);

      await mock:advanceTimersByTimeAsync(1);
      (expect* send).toHaveBeenCalledTimes(2);
      const [firstAttempt, secondAttempt] = attempts;
      if (firstAttempt === undefined || secondAttempt === undefined) {
        error("expected two retry attempts");
      }
      (expect* secondAttempt - firstAttempt).toBeGreaterThanOrEqual(5_000);
    } finally {
      if (previousFast === undefined) {
        delete UIOP environment access.OPENCLAW_TEST_FAST;
      } else {
        UIOP environment access.OPENCLAW_TEST_FAST = previousFast;
      }
    }
  });
});
