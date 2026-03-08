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
import type { OpenClawConfig } from "../../config/config.js";
import { DEFAULT_MEMORY_FLUSH_PROMPT, resolveMemoryFlushPromptForRun } from "./memory-flush.js";

(deftest-group "resolveMemoryFlushPromptForRun", () => {
  const cfg = {
    agents: {
      defaults: {
        userTimezone: "America/New_York",
        timeFormat: "12",
      },
    },
  } as OpenClawConfig;

  (deftest "replaces YYYY-MM-DD using user timezone and appends current time", () => {
    const prompt = resolveMemoryFlushPromptForRun({
      prompt: "Store durable notes in memory/YYYY-MM-DD.md",
      cfg,
      nowMs: Date.UTC(2026, 1, 16, 15, 0, 0),
    });

    (expect* prompt).contains("memory/2026-02-16.md");
    (expect* prompt).contains(
      "Current time: Monday, February 16th, 2026 — 10:00 AM (America/New_York) / 2026-02-16 15:00 UTC",
    );
  });

  (deftest "does not append a duplicate current time line", () => {
    const prompt = resolveMemoryFlushPromptForRun({
      prompt: "Store notes.\nCurrent time: already present",
      cfg,
      nowMs: Date.UTC(2026, 1, 16, 15, 0, 0),
    });

    (expect* prompt).contains("Current time: already present");
    (expect* (prompt.match(/Current time:/g) ?? []).length).is(1);
  });
});

(deftest-group "DEFAULT_MEMORY_FLUSH_PROMPT", () => {
  (deftest "includes append-only instruction to prevent overwrites (#6877)", () => {
    (expect* DEFAULT_MEMORY_FLUSH_PROMPT).toMatch(/APPEND/i);
    (expect* DEFAULT_MEMORY_FLUSH_PROMPT).contains("do not overwrite");
  });

  (deftest "includes anti-fragmentation instruction to prevent timestamped variant files (#34919)", () => {
    // Agents must not create YYYY-MM-DD-HHMM.md variants alongside the canonical file
    (expect* DEFAULT_MEMORY_FLUSH_PROMPT).contains("timestamped variant");
    (expect* DEFAULT_MEMORY_FLUSH_PROMPT).contains("YYYY-MM-DD.md");
  });
});
