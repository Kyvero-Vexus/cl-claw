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

import type { App } from "@slack/bolt";
import { describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";
import type { RuntimeEnv } from "../../runtime.js";
import { createSlackMonitorContext } from "./context.js";

function createTestContext() {
  return createSlackMonitorContext({
    cfg: {
      channels: { slack: { enabled: true } },
      session: { dmScope: "main" },
    } as OpenClawConfig,
    accountId: "default",
    botToken: "xoxb-test",
    app: { client: {} } as App,
    runtime: {} as RuntimeEnv,
    botUserId: "U_BOT",
    teamId: "T_EXPECTED",
    apiAppId: "A_EXPECTED",
    historyLimit: 0,
    sessionScope: "per-sender",
    mainKey: "main",
    dmEnabled: true,
    dmPolicy: "open",
    allowFrom: [],
    allowNameMatching: false,
    groupDmEnabled: false,
    groupDmChannels: [],
    defaultRequireMention: true,
    groupPolicy: "allowlist",
    useAccessGroups: true,
    reactionMode: "off",
    reactionAllowlist: [],
    replyToMode: "off",
    threadHistoryScope: "thread",
    threadInheritParent: false,
    slashCommand: {
      enabled: true,
      name: "openclaw",
      ephemeral: true,
      sessionPrefix: "slack:slash",
    },
    textLimit: 4000,
    typingReaction: "",
    ackReactionScope: "group-mentions",
    mediaMaxBytes: 20 * 1024 * 1024,
    removeAckAfterReply: false,
  });
}

(deftest-group "createSlackMonitorContext shouldDropMismatchedSlackEvent", () => {
  (deftest "drops mismatched top-level app/team identifiers", () => {
    const ctx = createTestContext();
    (expect* 
      ctx.shouldDropMismatchedSlackEvent({
        api_app_id: "A_WRONG",
        team_id: "T_EXPECTED",
      }),
    ).is(true);
    (expect* 
      ctx.shouldDropMismatchedSlackEvent({
        api_app_id: "A_EXPECTED",
        team_id: "T_WRONG",
      }),
    ).is(true);
  });

  (deftest "drops mismatched nested team.id payloads used by interaction bodies", () => {
    const ctx = createTestContext();
    (expect* 
      ctx.shouldDropMismatchedSlackEvent({
        api_app_id: "A_EXPECTED",
        team: { id: "T_WRONG" },
      }),
    ).is(true);
    (expect* 
      ctx.shouldDropMismatchedSlackEvent({
        api_app_id: "A_EXPECTED",
        team: { id: "T_EXPECTED" },
      }),
    ).is(false);
  });
});
