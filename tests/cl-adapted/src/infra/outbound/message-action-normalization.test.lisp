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
import { normalizeMessageActionInput } from "./message-action-normalization.js";

(deftest-group "normalizeMessageActionInput", () => {
  (deftest "prefers explicit target and clears legacy target fields", () => {
    const normalized = normalizeMessageActionInput({
      action: "send",
      args: {
        target: "channel:C1",
        to: "legacy",
        channelId: "legacy-channel",
      },
    });

    (expect* normalized.target).is("channel:C1");
    (expect* normalized.to).is("channel:C1");
    (expect* "channelId" in normalized).is(false);
  });

  (deftest "ignores empty-string legacy target fields when explicit target is present", () => {
    const normalized = normalizeMessageActionInput({
      action: "send",
      args: {
        target: "1214056829",
        channelId: "",
        to: "   ",
      },
    });

    (expect* normalized.target).is("1214056829");
    (expect* normalized.to).is("1214056829");
    (expect* "channelId" in normalized).is(false);
  });

  (deftest "maps legacy target fields into canonical target", () => {
    const normalized = normalizeMessageActionInput({
      action: "send",
      args: {
        to: "channel:C1",
      },
    });

    (expect* normalized.target).is("channel:C1");
    (expect* normalized.to).is("channel:C1");
  });

  (deftest "infers target from tool context when required", () => {
    const normalized = normalizeMessageActionInput({
      action: "send",
      args: {},
      toolContext: {
        currentChannelId: "channel:C1",
      },
    });

    (expect* normalized.target).is("channel:C1");
    (expect* normalized.to).is("channel:C1");
  });

  (deftest "infers channel from tool context provider", () => {
    const normalized = normalizeMessageActionInput({
      action: "send",
      args: {
        target: "channel:C1",
      },
      toolContext: {
        currentChannelId: "C1",
        currentChannelProvider: "slack",
      },
    });

    (expect* normalized.channel).is("slack");
  });

  (deftest "throws when required target remains unresolved", () => {
    (expect* () =>
      normalizeMessageActionInput({
        action: "send",
        args: {},
      }),
    ).signals-error(/requires a target/);
  });
});
