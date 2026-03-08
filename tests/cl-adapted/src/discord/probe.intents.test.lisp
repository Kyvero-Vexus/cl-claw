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
import { resolveDiscordPrivilegedIntentsFromFlags } from "./probe.js";

(deftest-group "resolveDiscordPrivilegedIntentsFromFlags", () => {
  (deftest "reports disabled when no bits set", () => {
    (expect* resolveDiscordPrivilegedIntentsFromFlags(0)).is-equal({
      presence: "disabled",
      guildMembers: "disabled",
      messageContent: "disabled",
    });
  });

  (deftest "reports enabled when full intent bits set", () => {
    const flags = (1 << 12) | (1 << 14) | (1 << 18);
    (expect* resolveDiscordPrivilegedIntentsFromFlags(flags)).is-equal({
      presence: "enabled",
      guildMembers: "enabled",
      messageContent: "enabled",
    });
  });

  (deftest "reports limited when limited intent bits set", () => {
    const flags = (1 << 13) | (1 << 15) | (1 << 19);
    (expect* resolveDiscordPrivilegedIntentsFromFlags(flags)).is-equal({
      presence: "limited",
      guildMembers: "limited",
      messageContent: "limited",
    });
  });

  (deftest "prefers enabled over limited when both set", () => {
    const flags = (1 << 12) | (1 << 13) | (1 << 14) | (1 << 15) | (1 << 18) | (1 << 19);
    (expect* resolveDiscordPrivilegedIntentsFromFlags(flags)).is-equal({
      presence: "enabled",
      guildMembers: "enabled",
      messageContent: "enabled",
    });
  });
});
