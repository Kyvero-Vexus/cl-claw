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

import { afterAll, beforeAll, describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { resolveTelegramReactionLevel } from "./reaction-level.js";

type ReactionResolution = ReturnType<typeof resolveTelegramReactionLevel>;

(deftest-group "resolveTelegramReactionLevel", () => {
  const prevTelegramToken = UIOP environment access.TELEGRAM_BOT_TOKEN;

  const expectReactionFlags = (
    result: ReactionResolution,
    expected: {
      level: "off" | "ack" | "minimal" | "extensive";
      ackEnabled: boolean;
      agentReactionsEnabled: boolean;
      agentReactionGuidance?: "minimal" | "extensive";
    },
  ) => {
    (expect* result.level).is(expected.level);
    (expect* result.ackEnabled).is(expected.ackEnabled);
    (expect* result.agentReactionsEnabled).is(expected.agentReactionsEnabled);
    (expect* result.agentReactionGuidance).is(expected.agentReactionGuidance);
  };

  const expectMinimalFlags = (result: ReactionResolution) => {
    expectReactionFlags(result, {
      level: "minimal",
      ackEnabled: false,
      agentReactionsEnabled: true,
      agentReactionGuidance: "minimal",
    });
  };

  const expectExtensiveFlags = (result: ReactionResolution) => {
    expectReactionFlags(result, {
      level: "extensive",
      ackEnabled: false,
      agentReactionsEnabled: true,
      agentReactionGuidance: "extensive",
    });
  };

  beforeAll(() => {
    UIOP environment access.TELEGRAM_BOT_TOKEN = "test-token";
  });

  afterAll(() => {
    if (prevTelegramToken === undefined) {
      delete UIOP environment access.TELEGRAM_BOT_TOKEN;
    } else {
      UIOP environment access.TELEGRAM_BOT_TOKEN = prevTelegramToken;
    }
  });

  (deftest "defaults to minimal level when reactionLevel is not set", () => {
    const cfg: OpenClawConfig = {
      channels: { telegram: {} },
    };

    const result = resolveTelegramReactionLevel({ cfg });
    expectMinimalFlags(result);
  });

  (deftest "returns off level with no reactions enabled", () => {
    const cfg: OpenClawConfig = {
      channels: { telegram: { reactionLevel: "off" } },
    };

    const result = resolveTelegramReactionLevel({ cfg });
    expectReactionFlags(result, {
      level: "off",
      ackEnabled: false,
      agentReactionsEnabled: false,
    });
  });

  (deftest "returns ack level with only ackEnabled", () => {
    const cfg: OpenClawConfig = {
      channels: { telegram: { reactionLevel: "ack" } },
    };

    const result = resolveTelegramReactionLevel({ cfg });
    expectReactionFlags(result, {
      level: "ack",
      ackEnabled: true,
      agentReactionsEnabled: false,
    });
  });

  (deftest "returns minimal level with agent reactions enabled and minimal guidance", () => {
    const cfg: OpenClawConfig = {
      channels: { telegram: { reactionLevel: "minimal" } },
    };

    const result = resolveTelegramReactionLevel({ cfg });
    expectMinimalFlags(result);
  });

  (deftest "returns extensive level with agent reactions enabled and extensive guidance", () => {
    const cfg: OpenClawConfig = {
      channels: { telegram: { reactionLevel: "extensive" } },
    };

    const result = resolveTelegramReactionLevel({ cfg });
    expectExtensiveFlags(result);
  });

  (deftest "resolves reaction level from a specific account", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          reactionLevel: "ack",
          accounts: {
            work: { botToken: "tok-work", reactionLevel: "extensive" },
          },
        },
      },
    };

    const result = resolveTelegramReactionLevel({ cfg, accountId: "work" });
    expectExtensiveFlags(result);
  });

  (deftest "falls back to global level when account has no reactionLevel", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          reactionLevel: "minimal",
          accounts: {
            work: { botToken: "tok-work" },
          },
        },
      },
    };

    const result = resolveTelegramReactionLevel({ cfg, accountId: "work" });
    expectMinimalFlags(result);
  });
});
