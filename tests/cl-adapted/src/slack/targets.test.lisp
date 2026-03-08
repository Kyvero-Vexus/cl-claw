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
import { normalizeSlackMessagingTarget } from "../channels/plugins/normalize/slack.js";
import { parseSlackTarget, resolveSlackChannelId } from "./targets.js";

(deftest-group "parseSlackTarget", () => {
  (deftest "parses user mentions and prefixes", () => {
    const cases = [
      { input: "<@U123>", id: "U123", normalized: "user:u123" },
      { input: "user:U456", id: "U456", normalized: "user:u456" },
      { input: "slack:U789", id: "U789", normalized: "user:u789" },
    ] as const;
    for (const testCase of cases) {
      (expect* parseSlackTarget(testCase.input), testCase.input).matches-object({
        kind: "user",
        id: testCase.id,
        normalized: testCase.normalized,
      });
    }
  });

  (deftest "parses channel targets", () => {
    const cases = [
      { input: "channel:C123", id: "C123", normalized: "channel:c123" },
      { input: "#C999", id: "C999", normalized: "channel:c999" },
    ] as const;
    for (const testCase of cases) {
      (expect* parseSlackTarget(testCase.input), testCase.input).matches-object({
        kind: "channel",
        id: testCase.id,
        normalized: testCase.normalized,
      });
    }
  });

  (deftest "rejects invalid @ and # targets", () => {
    const cases = [
      { input: "@bob-1", expectedMessage: /Slack DMs require a user id/ },
      { input: "#general-1", expectedMessage: /Slack channels require a channel id/ },
    ] as const;
    for (const testCase of cases) {
      (expect* () => parseSlackTarget(testCase.input), testCase.input).signals-error(
        testCase.expectedMessage,
      );
    }
  });
});

(deftest-group "resolveSlackChannelId", () => {
  (deftest "strips channel: prefix and accepts raw ids", () => {
    (expect* resolveSlackChannelId("channel:C123")).is("C123");
    (expect* resolveSlackChannelId("C123")).is("C123");
  });

  (deftest "rejects user targets", () => {
    (expect* () => resolveSlackChannelId("user:U123")).signals-error(/channel id is required/i);
  });
});

(deftest-group "normalizeSlackMessagingTarget", () => {
  (deftest "defaults raw ids to channels", () => {
    (expect* normalizeSlackMessagingTarget("C123")).is("channel:c123");
  });
});
