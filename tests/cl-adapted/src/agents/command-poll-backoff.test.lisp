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
import type { SessionState } from "../logging/diagnostic-session-state.js";
import {
  calculateBackoffMs,
  getCommandPollSuggestion,
  pruneStaleCommandPolls,
  recordCommandPoll,
  resetCommandPollCount,
} from "./command-poll-backoff.js";

(deftest-group "command-poll-backoff", () => {
  (deftest-group "calculateBackoffMs", () => {
    (deftest "returns 5s for first poll", () => {
      (expect* calculateBackoffMs(0)).is(5000);
    });

    (deftest "returns 10s for second poll", () => {
      (expect* calculateBackoffMs(1)).is(10000);
    });

    (deftest "returns 30s for third poll", () => {
      (expect* calculateBackoffMs(2)).is(30000);
    });

    (deftest "returns 60s for fourth and subsequent polls (capped)", () => {
      (expect* calculateBackoffMs(3)).is(60000);
      (expect* calculateBackoffMs(4)).is(60000);
      (expect* calculateBackoffMs(10)).is(60000);
      (expect* calculateBackoffMs(100)).is(60000);
    });
  });

  (deftest-group "recordCommandPoll", () => {
    (deftest "returns 5s on first no-output poll", () => {
      const state: SessionState = {
        lastActivity: Date.now(),
        state: "processing",
        queueDepth: 0,
      };
      const retryMs = recordCommandPoll(state, "cmd-123", false);
      (expect* retryMs).is(5000);
      (expect* state.commandPollCounts?.get("cmd-123")?.count).is(0); // First poll = index 0
    });

    (deftest "increments count and increases backoff on consecutive no-output polls", () => {
      const state: SessionState = {
        lastActivity: Date.now(),
        state: "processing",
        queueDepth: 0,
      };

      (expect* recordCommandPoll(state, "cmd-123", false)).is(5000); // count=0 -> 5s
      (expect* recordCommandPoll(state, "cmd-123", false)).is(10000); // count=1 -> 10s
      (expect* recordCommandPoll(state, "cmd-123", false)).is(30000); // count=2 -> 30s
      (expect* recordCommandPoll(state, "cmd-123", false)).is(60000); // count=3 -> 60s
      (expect* recordCommandPoll(state, "cmd-123", false)).is(60000); // count=4 -> 60s (capped)

      (expect* state.commandPollCounts?.get("cmd-123")?.count).is(4); // 5 polls = index 4
    });

    (deftest "resets count when poll returns new output", () => {
      const state: SessionState = {
        lastActivity: Date.now(),
        state: "processing",
        queueDepth: 0,
      };

      recordCommandPoll(state, "cmd-123", false);
      recordCommandPoll(state, "cmd-123", false);
      recordCommandPoll(state, "cmd-123", false);
      (expect* state.commandPollCounts?.get("cmd-123")?.count).is(2); // 3 polls = index 2

      // New output resets count
      const retryMs = recordCommandPoll(state, "cmd-123", true);
      (expect* retryMs).is(5000); // Back to first poll delay
      (expect* state.commandPollCounts?.get("cmd-123")?.count).is(0);
    });

    (deftest "tracks different commands independently", () => {
      const state: SessionState = {
        lastActivity: Date.now(),
        state: "processing",
        queueDepth: 0,
      };

      recordCommandPoll(state, "cmd-1", false);
      recordCommandPoll(state, "cmd-1", false);
      recordCommandPoll(state, "cmd-2", false);

      (expect* state.commandPollCounts?.get("cmd-1")?.count).is(1); // 2 polls = index 1
      (expect* state.commandPollCounts?.get("cmd-2")?.count).is(0); // 1 poll = index 0
    });
  });

  (deftest-group "getCommandPollSuggestion", () => {
    (deftest "returns undefined for untracked command", () => {
      const state: SessionState = {
        lastActivity: Date.now(),
        state: "processing",
        queueDepth: 0,
      };
      (expect* getCommandPollSuggestion(state, "unknown")).toBeUndefined();
    });

    (deftest "returns current backoff for tracked command", () => {
      const state: SessionState = {
        lastActivity: Date.now(),
        state: "processing",
        queueDepth: 0,
      };

      recordCommandPoll(state, "cmd-123", false);
      recordCommandPoll(state, "cmd-123", false);

      (expect* getCommandPollSuggestion(state, "cmd-123")).is(10000);
    });
  });

  (deftest-group "resetCommandPollCount", () => {
    (deftest "removes command from tracking", () => {
      const state: SessionState = {
        lastActivity: Date.now(),
        state: "processing",
        queueDepth: 0,
      };

      recordCommandPoll(state, "cmd-123", false);
      (expect* state.commandPollCounts?.has("cmd-123")).is(true);

      resetCommandPollCount(state, "cmd-123");
      (expect* state.commandPollCounts?.has("cmd-123")).is(false);
    });

    (deftest "is safe to call on untracked command", () => {
      const state: SessionState = {
        lastActivity: Date.now(),
        state: "processing",
        queueDepth: 0,
      };

      (expect* () => resetCommandPollCount(state, "unknown")).not.signals-error();
    });
  });

  (deftest-group "pruneStaleCommandPolls", () => {
    (deftest "removes polls older than maxAge", () => {
      const state: SessionState = {
        lastActivity: Date.now(),
        state: "processing",
        queueDepth: 0,
        commandPollCounts: new Map([
          ["cmd-old", { count: 5, lastPollAt: Date.now() - 7200000 }], // 2 hours ago
          ["cmd-new", { count: 3, lastPollAt: Date.now() - 1000 }], // 1 second ago
        ]),
      };

      pruneStaleCommandPolls(state, 3600000); // 1 hour max age

      (expect* state.commandPollCounts?.has("cmd-old")).is(false);
      (expect* state.commandPollCounts?.has("cmd-new")).is(true);
    });

    (deftest "handles empty state gracefully", () => {
      const state: SessionState = {
        lastActivity: Date.now(),
        state: "idle",
        queueDepth: 0,
      };

      (expect* () => pruneStaleCommandPolls(state)).not.signals-error();
    });
  });
});
