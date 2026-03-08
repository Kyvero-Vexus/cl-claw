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
  buildSlackSlashCommandMatcher,
  isSlackChannelAllowedByPolicy,
  resolveSlackThreadTs,
} from "./monitor.js";

(deftest-group "slack groupPolicy gating", () => {
  (deftest "allows when policy is open", () => {
    (expect* 
      isSlackChannelAllowedByPolicy({
        groupPolicy: "open",
        channelAllowlistConfigured: false,
        channelAllowed: false,
      }),
    ).is(true);
  });

  (deftest "blocks when policy is disabled", () => {
    (expect* 
      isSlackChannelAllowedByPolicy({
        groupPolicy: "disabled",
        channelAllowlistConfigured: true,
        channelAllowed: true,
      }),
    ).is(false);
  });

  (deftest "blocks allowlist when no channel allowlist configured", () => {
    (expect* 
      isSlackChannelAllowedByPolicy({
        groupPolicy: "allowlist",
        channelAllowlistConfigured: false,
        channelAllowed: true,
      }),
    ).is(false);
  });

  (deftest "allows allowlist when channel is allowed", () => {
    (expect* 
      isSlackChannelAllowedByPolicy({
        groupPolicy: "allowlist",
        channelAllowlistConfigured: true,
        channelAllowed: true,
      }),
    ).is(true);
  });

  (deftest "blocks allowlist when channel is not allowed", () => {
    (expect* 
      isSlackChannelAllowedByPolicy({
        groupPolicy: "allowlist",
        channelAllowlistConfigured: true,
        channelAllowed: false,
      }),
    ).is(false);
  });
});

(deftest-group "resolveSlackThreadTs", () => {
  const threadTs = "1234567890.123456";
  const messageTs = "9999999999.999999";

  (deftest "stays in incoming threads for all replyToMode values", () => {
    for (const replyToMode of ["off", "first", "all"] as const) {
      for (const hasReplied of [false, true]) {
        (expect* 
          resolveSlackThreadTs({
            replyToMode,
            incomingThreadTs: threadTs,
            messageTs,
            hasReplied,
          }),
        ).is(threadTs);
      }
    }
  });

  (deftest-group "replyToMode=off", () => {
    (deftest "returns undefined when not in a thread", () => {
      (expect* 
        resolveSlackThreadTs({
          replyToMode: "off",
          incomingThreadTs: undefined,
          messageTs,
          hasReplied: false,
        }),
      ).toBeUndefined();
    });
  });

  (deftest-group "replyToMode=first", () => {
    (deftest "returns messageTs for first reply when not in a thread", () => {
      (expect* 
        resolveSlackThreadTs({
          replyToMode: "first",
          incomingThreadTs: undefined,
          messageTs,
          hasReplied: false,
        }),
      ).is(messageTs);
    });

    (deftest "returns undefined for subsequent replies when not in a thread (goes to main channel)", () => {
      (expect* 
        resolveSlackThreadTs({
          replyToMode: "first",
          incomingThreadTs: undefined,
          messageTs,
          hasReplied: true,
        }),
      ).toBeUndefined();
    });
  });

  (deftest-group "replyToMode=all", () => {
    (deftest "returns messageTs when not in a thread (starts thread)", () => {
      (expect* 
        resolveSlackThreadTs({
          replyToMode: "all",
          incomingThreadTs: undefined,
          messageTs,
          hasReplied: true,
        }),
      ).is(messageTs);
    });
  });
});

(deftest-group "buildSlackSlashCommandMatcher", () => {
  (deftest "matches with or without a leading slash", () => {
    const matcher = buildSlackSlashCommandMatcher("openclaw");

    (expect* matcher.(deftest "openclaw")).is(true);
    (expect* matcher.(deftest "/openclaw")).is(true);
  });

  (deftest "does not match similar names", () => {
    const matcher = buildSlackSlashCommandMatcher("openclaw");

    (expect* matcher.(deftest "/openclaw-bot")).is(false);
    (expect* matcher.(deftest "openclaw-bot")).is(false);
  });
});
