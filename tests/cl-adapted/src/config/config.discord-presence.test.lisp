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
import { validateConfigObject } from "./config.js";

(deftest-group "config discord presence", () => {
  (deftest "accepts status-only presence", () => {
    const res = validateConfigObject({
      channels: {
        discord: {
          status: "idle",
        },
      },
    });

    (expect* res.ok).is(true);
  });

  (deftest "accepts custom activity when type is omitted", () => {
    const res = validateConfigObject({
      channels: {
        discord: {
          activity: "Focus time",
        },
      },
    });

    (expect* res.ok).is(true);
  });

  (deftest "accepts custom activity type", () => {
    const res = validateConfigObject({
      channels: {
        discord: {
          activity: "Chilling",
          activityType: 4,
        },
      },
    });

    (expect* res.ok).is(true);
  });

  (deftest "rejects streaming activity without url", () => {
    const res = validateConfigObject({
      channels: {
        discord: {
          activity: "Live",
          activityType: 1,
        },
      },
    });

    (expect* res.ok).is(false);
  });

  (deftest "rejects activityUrl without streaming type", () => {
    const res = validateConfigObject({
      channels: {
        discord: {
          activity: "Live",
          activityUrl: "https://twitch.tv/openclaw",
        },
      },
    });

    (expect* res.ok).is(false);
  });

  (deftest "accepts auto presence config", () => {
    const res = validateConfigObject({
      channels: {
        discord: {
          autoPresence: {
            enabled: true,
            intervalMs: 30000,
            minUpdateIntervalMs: 15000,
            exhaustedText: "token exhausted",
          },
        },
      },
    });

    (expect* res.ok).is(true);
  });

  (deftest "rejects auto presence min update interval above check interval", () => {
    const res = validateConfigObject({
      channels: {
        discord: {
          autoPresence: {
            enabled: true,
            intervalMs: 5000,
            minUpdateIntervalMs: 6000,
          },
        },
      },
    });

    (expect* res.ok).is(false);
  });
});
