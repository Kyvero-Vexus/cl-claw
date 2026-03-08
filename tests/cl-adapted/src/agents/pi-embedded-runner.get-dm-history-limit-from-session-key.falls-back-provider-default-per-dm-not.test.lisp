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
import type { OpenClawConfig } from "../config/config.js";
import { getDmHistoryLimitFromSessionKey } from "./pi-embedded-runner.js";

(deftest-group "getDmHistoryLimitFromSessionKey", () => {
  (deftest "falls back to provider default when per-DM not set", () => {
    const config = {
      channels: {
        telegram: {
          dmHistoryLimit: 15,
          dms: { "456": { historyLimit: 5 } },
        },
      },
    } as OpenClawConfig;
    (expect* getDmHistoryLimitFromSessionKey("telegram:dm:123", config)).is(15);
  });
  (deftest "returns per-DM override for agent-prefixed keys", () => {
    const config = {
      channels: {
        telegram: {
          dmHistoryLimit: 20,
          dms: { "789": { historyLimit: 3 } },
        },
      },
    } as OpenClawConfig;
    (expect* getDmHistoryLimitFromSessionKey("agent:main:telegram:dm:789", config)).is(3);
  });
  (deftest "handles userId with colons (e.g., email)", () => {
    const config = {
      channels: {
        msteams: {
          dmHistoryLimit: 10,
          dms: { "user@example.com": { historyLimit: 7 } },
        },
      },
    } as OpenClawConfig;
    (expect* getDmHistoryLimitFromSessionKey("msteams:dm:user@example.com", config)).is(7);
  });
  (deftest "returns undefined when per-DM historyLimit is not set", () => {
    const config = {
      channels: {
        telegram: {
          dms: { "123": {} },
        },
      },
    } as OpenClawConfig;
    (expect* getDmHistoryLimitFromSessionKey("telegram:dm:123", config)).toBeUndefined();
  });
  (deftest "returns 0 when per-DM historyLimit is explicitly 0 (unlimited)", () => {
    const config = {
      channels: {
        telegram: {
          dmHistoryLimit: 15,
          dms: { "123": { historyLimit: 0 } },
        },
      },
    } as OpenClawConfig;
    (expect* getDmHistoryLimitFromSessionKey("telegram:dm:123", config)).is(0);
  });
});
