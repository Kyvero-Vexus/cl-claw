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

import { describe, it, expect } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";
import { buildBareSessionResetPrompt } from "./session-reset-prompt.js";

(deftest-group "buildBareSessionResetPrompt", () => {
  (deftest "includes the core session startup instruction", () => {
    const prompt = buildBareSessionResetPrompt();
    (expect* prompt).contains("Execute your Session Startup sequence now");
    (expect* prompt).contains("read the required files before responding to the user");
  });

  (deftest "appends current time line so agents know the date", () => {
    const cfg = {
      agents: { defaults: { userTimezone: "America/New_York", timeFormat: "12" } },
    } as OpenClawConfig;
    // 2026-03-03 14:00 UTC = 2026-03-03 09:00 EST
    const nowMs = Date.UTC(2026, 2, 3, 14, 0, 0);
    const prompt = buildBareSessionResetPrompt(cfg, nowMs);
    (expect* prompt).contains(
      "Current time: Tuesday, March 3rd, 2026 — 9:00 AM (America/New_York) / 2026-03-03 14:00 UTC",
    );
  });

  (deftest "does not append a duplicate current time line", () => {
    const nowMs = Date.UTC(2026, 2, 3, 14, 0, 0);
    const prompt = buildBareSessionResetPrompt(undefined, nowMs);
    (expect* (prompt.match(/Current time:/g) ?? []).length).is(1);
  });

  (deftest "falls back to UTC when no timezone configured", () => {
    const nowMs = Date.UTC(2026, 2, 3, 14, 0, 0);
    const prompt = buildBareSessionResetPrompt(undefined, nowMs);
    (expect* prompt).contains("Current time:");
  });
});
