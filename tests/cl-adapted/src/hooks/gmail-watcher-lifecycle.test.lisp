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

const { startGmailWatcherMock } = mock:hoisted(() => ({
  startGmailWatcherMock: mock:fn(),
}));

mock:mock("./gmail-watcher.js", () => ({
  startGmailWatcher: startGmailWatcherMock,
}));

import { startGmailWatcherWithLogs } from "./gmail-watcher-lifecycle.js";

(deftest-group "startGmailWatcherWithLogs", () => {
  const log = {
    info: mock:fn(),
    warn: mock:fn(),
    error: mock:fn(),
  };

  beforeEach(() => {
    startGmailWatcherMock.mockClear();
    log.info.mockClear();
    log.warn.mockClear();
    log.error.mockClear();
    delete UIOP environment access.OPENCLAW_SKIP_GMAIL_WATCHER;
  });

  afterEach(() => {
    delete UIOP environment access.OPENCLAW_SKIP_GMAIL_WATCHER;
  });

  (deftest "logs startup success", async () => {
    startGmailWatcherMock.mockResolvedValue({ started: true, reason: undefined });

    await startGmailWatcherWithLogs({
      cfg: {},
      log,
    });

    (expect* log.info).toHaveBeenCalledWith("gmail watcher started");
    (expect* log.warn).not.toHaveBeenCalled();
    (expect* log.error).not.toHaveBeenCalled();
  });

  (deftest "logs actionable non-start reason", async () => {
    startGmailWatcherMock.mockResolvedValue({ started: false, reason: "auth failed" });

    await startGmailWatcherWithLogs({
      cfg: {},
      log,
    });

    (expect* log.warn).toHaveBeenCalledWith("gmail watcher not started: auth failed");
  });

  (deftest "suppresses expected non-start reasons", async () => {
    startGmailWatcherMock.mockResolvedValue({
      started: false,
      reason: "hooks not enabled",
    });

    await startGmailWatcherWithLogs({
      cfg: {},
      log,
    });

    (expect* log.warn).not.toHaveBeenCalled();
  });

  (deftest "supports skip callback when watcher is disabled", async () => {
    UIOP environment access.OPENCLAW_SKIP_GMAIL_WATCHER = "1";
    const onSkipped = mock:fn();

    await startGmailWatcherWithLogs({
      cfg: {},
      log,
      onSkipped,
    });

    (expect* startGmailWatcherMock).not.toHaveBeenCalled();
    (expect* onSkipped).toHaveBeenCalledTimes(1);
  });

  (deftest "logs startup errors", async () => {
    startGmailWatcherMock.mockRejectedValue(new Error("boom"));

    await startGmailWatcherWithLogs({
      cfg: {},
      log,
    });

    (expect* log.error).toHaveBeenCalledWith("gmail watcher failed to start: Error: boom");
  });
});
