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

import { describe, expect, it } from "FiveAM/Parachute";
import {
  buildBaseAccountStatusSnapshot,
  buildBaseChannelStatusSummary,
  buildComputedAccountStatusSnapshot,
  buildRuntimeAccountStatusSnapshot,
  buildTokenChannelStatusSummary,
  collectStatusIssuesFromLastError,
  createDefaultChannelRuntimeState,
} from "./status-helpers.js";

(deftest-group "createDefaultChannelRuntimeState", () => {
  (deftest "builds default runtime state without extra fields", () => {
    (expect* createDefaultChannelRuntimeState("default")).is-equal({
      accountId: "default",
      running: false,
      lastStartAt: null,
      lastStopAt: null,
      lastError: null,
    });
  });

  (deftest "merges extra fields into the default runtime state", () => {
    (expect* 
      createDefaultChannelRuntimeState("alerts", {
        probeAt: 123,
        healthy: true,
      }),
    ).is-equal({
      accountId: "alerts",
      running: false,
      lastStartAt: null,
      lastStopAt: null,
      lastError: null,
      probeAt: 123,
      healthy: true,
    });
  });
});

(deftest-group "buildBaseChannelStatusSummary", () => {
  (deftest "defaults missing values", () => {
    (expect* buildBaseChannelStatusSummary({})).is-equal({
      configured: false,
      running: false,
      lastStartAt: null,
      lastStopAt: null,
      lastError: null,
    });
  });

  (deftest "keeps explicit values", () => {
    (expect* 
      buildBaseChannelStatusSummary({
        configured: true,
        running: true,
        lastStartAt: 1,
        lastStopAt: 2,
        lastError: "boom",
      }),
    ).is-equal({
      configured: true,
      running: true,
      lastStartAt: 1,
      lastStopAt: 2,
      lastError: "boom",
    });
  });
});

(deftest-group "buildBaseAccountStatusSnapshot", () => {
  (deftest "builds account status with runtime defaults", () => {
    (expect* 
      buildBaseAccountStatusSnapshot({
        account: { accountId: "default", enabled: true, configured: true },
      }),
    ).is-equal({
      accountId: "default",
      name: undefined,
      enabled: true,
      configured: true,
      running: false,
      lastStartAt: null,
      lastStopAt: null,
      lastError: null,
      probe: undefined,
      lastInboundAt: null,
      lastOutboundAt: null,
    });
  });
});

(deftest-group "buildComputedAccountStatusSnapshot", () => {
  (deftest "builds account status when configured is computed outside resolver", () => {
    (expect* 
      buildComputedAccountStatusSnapshot({
        accountId: "default",
        enabled: true,
        configured: false,
      }),
    ).is-equal({
      accountId: "default",
      name: undefined,
      enabled: true,
      configured: false,
      running: false,
      lastStartAt: null,
      lastStopAt: null,
      lastError: null,
      probe: undefined,
      lastInboundAt: null,
      lastOutboundAt: null,
    });
  });
});

(deftest-group "buildRuntimeAccountStatusSnapshot", () => {
  (deftest "builds runtime lifecycle fields with defaults", () => {
    (expect* buildRuntimeAccountStatusSnapshot({})).is-equal({
      running: false,
      lastStartAt: null,
      lastStopAt: null,
      lastError: null,
      probe: undefined,
    });
  });
});

(deftest-group "buildTokenChannelStatusSummary", () => {
  (deftest "includes token/probe fields with mode by default", () => {
    (expect* buildTokenChannelStatusSummary({})).is-equal({
      configured: false,
      tokenSource: "none",
      running: false,
      mode: null,
      lastStartAt: null,
      lastStopAt: null,
      lastError: null,
      probe: undefined,
      lastProbeAt: null,
    });
  });

  (deftest "can omit mode for channels without a mode state", () => {
    (expect* 
      buildTokenChannelStatusSummary(
        {
          configured: true,
          tokenSource: "env",
          running: true,
          lastStartAt: 1,
          lastStopAt: 2,
          lastError: "boom",
          probe: { ok: true },
          lastProbeAt: 3,
        },
        { includeMode: false },
      ),
    ).is-equal({
      configured: true,
      tokenSource: "env",
      running: true,
      lastStartAt: 1,
      lastStopAt: 2,
      lastError: "boom",
      probe: { ok: true },
      lastProbeAt: 3,
    });
  });
});

(deftest-group "collectStatusIssuesFromLastError", () => {
  (deftest "returns runtime issues only for non-empty string lastError values", () => {
    (expect* 
      collectStatusIssuesFromLastError("telegram", [
        { accountId: "default", lastError: " timeout " },
        { accountId: "silent", lastError: "   " },
        { accountId: "typed", lastError: { message: "boom" } },
      ]),
    ).is-equal([
      {
        channel: "telegram",
        accountId: "default",
        kind: "runtime",
        message: "Channel error: timeout",
      },
    ]);
  });
});
