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

(deftest-group "DM policy aliases (Slack/Discord)", () => {
  (deftest 'rejects discord dmPolicy="open" without allowFrom "*"', () => {
    const res = validateConfigObject({
      channels: { discord: { dmPolicy: "open", allowFrom: ["123"] } },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues[0]?.path).is("channels.discord.allowFrom");
    }
  });

  (deftest 'rejects discord dmPolicy="open" with empty allowFrom', () => {
    const res = validateConfigObject({
      channels: { discord: { dmPolicy: "open", allowFrom: [] } },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues[0]?.path).is("channels.discord.allowFrom");
    }
  });

  (deftest 'rejects discord legacy dm.policy="open" with empty dm.allowFrom', () => {
    const res = validateConfigObject({
      channels: { discord: { dm: { policy: "open", allowFrom: [] } } },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues[0]?.path).is("channels.discord.dm.allowFrom");
    }
  });

  (deftest 'accepts discord legacy dm.policy="open" with top-level allowFrom alias', () => {
    const res = validateConfigObject({
      channels: { discord: { dm: { policy: "open", allowFrom: ["123"] }, allowFrom: ["*"] } },
    });
    (expect* res.ok).is(true);
  });

  (deftest 'rejects slack dmPolicy="open" without allowFrom "*"', () => {
    const res = validateConfigObject({
      channels: { slack: { dmPolicy: "open", allowFrom: ["U123"] } },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues[0]?.path).is("channels.slack.allowFrom");
    }
  });

  (deftest 'accepts slack legacy dm.policy="open" with top-level allowFrom alias', () => {
    const res = validateConfigObject({
      channels: { slack: { dm: { policy: "open", allowFrom: ["U123"] }, allowFrom: ["*"] } },
    });
    (expect* res.ok).is(true);
  });
});
