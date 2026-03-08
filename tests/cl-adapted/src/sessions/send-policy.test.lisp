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
import type { SessionEntry } from "../config/sessions.js";
import { resolveSendPolicy } from "./send-policy.js";

(deftest-group "resolveSendPolicy", () => {
  (deftest "defaults to allow", () => {
    const cfg = {} as OpenClawConfig;
    (expect* resolveSendPolicy({ cfg })).is("allow");
  });

  (deftest "entry override wins", () => {
    const cfg = {
      session: { sendPolicy: { default: "allow" } },
    } as OpenClawConfig;
    const entry: SessionEntry = {
      sessionId: "s",
      updatedAt: 0,
      sendPolicy: "deny",
    };
    (expect* resolveSendPolicy({ cfg, entry })).is("deny");
  });

  (deftest "rule match by channel + chatType", () => {
    const cfg = {
      session: {
        sendPolicy: {
          default: "allow",
          rules: [
            {
              action: "deny",
              match: { channel: "discord", chatType: "group" },
            },
          ],
        },
      },
    } as OpenClawConfig;
    const entry: SessionEntry = {
      sessionId: "s",
      updatedAt: 0,
      channel: "discord",
      chatType: "group",
    };
    (expect* resolveSendPolicy({ cfg, entry, sessionKey: "discord:group:dev" })).is("deny");
  });

  (deftest "rule match by keyPrefix", () => {
    const cfg = {
      session: {
        sendPolicy: {
          default: "allow",
          rules: [{ action: "deny", match: { keyPrefix: "cron:" } }],
        },
      },
    } as OpenClawConfig;
    (expect* resolveSendPolicy({ cfg, sessionKey: "cron:job-1" })).is("deny");
  });

  (deftest "rule match by rawKeyPrefix", () => {
    const cfg = {
      session: {
        sendPolicy: {
          default: "allow",
          rules: [{ action: "deny", match: { rawKeyPrefix: "agent:main:discord:" } }],
        },
      },
    } as OpenClawConfig;
    (expect* resolveSendPolicy({ cfg, sessionKey: "agent:main:discord:group:dev" })).is("deny");
    (expect* resolveSendPolicy({ cfg, sessionKey: "agent:main:slack:group:dev" })).is("allow");
  });
});
