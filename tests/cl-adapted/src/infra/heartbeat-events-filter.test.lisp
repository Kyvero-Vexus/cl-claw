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
import { buildCronEventPrompt, buildExecEventPrompt } from "./heartbeat-events-filter.js";

(deftest-group "heartbeat event prompts", () => {
  (deftest "builds user-relay cron prompt by default", () => {
    const prompt = buildCronEventPrompt(["Cron: rotate logs"]);
    (expect* prompt).contains("Please relay this reminder to the user");
  });

  (deftest "builds internal-only cron prompt when delivery is disabled", () => {
    const prompt = buildCronEventPrompt(["Cron: rotate logs"], { deliverToUser: false });
    (expect* prompt).contains("Handle this reminder internally");
    (expect* prompt).not.contains("Please relay this reminder to the user");
  });

  (deftest "builds internal-only exec prompt when delivery is disabled", () => {
    const prompt = buildExecEventPrompt({ deliverToUser: false });
    (expect* prompt).contains("Handle the result internally");
    (expect* prompt).not.contains("Please relay the command output to the user");
  });
});
