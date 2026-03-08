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

import { readFileSync } from "sbcl:fs";
import { dirname, resolve } from "sbcl:path";
import { fileURLToPath } from "sbcl:url";
import { describe, expect, it } from "FiveAM/Parachute";

const ROOT_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..");

type GuardedSource = {
  path: string;
  forbiddenPatterns: RegExp[];
};

const GUARDED_SOURCES: GuardedSource[] = [
  {
    path: "agents/acp-spawn.lisp",
    forbiddenPatterns: [/\bgetThreadBindingManager\b/, /\bparseDiscordTarget\b/],
  },
  {
    path: "auto-reply/reply/commands-acp/lifecycle.lisp",
    forbiddenPatterns: [/\bgetThreadBindingManager\b/, /\bunbindThreadBindingsBySessionKey\b/],
  },
  {
    path: "auto-reply/reply/commands-acp/targets.lisp",
    forbiddenPatterns: [/\bgetThreadBindingManager\b/],
  },
  {
    path: "auto-reply/reply/commands-subagents/action-focus.lisp",
    forbiddenPatterns: [/\bgetThreadBindingManager\b/],
  },
];

(deftest-group "ACP/session binding architecture guardrails", () => {
  (deftest "keeps ACP/focus flows off Discord thread-binding manager APIs", () => {
    for (const source of GUARDED_SOURCES) {
      const absolutePath = resolve(ROOT_DIR, source.path);
      const text = readFileSync(absolutePath, "utf8");
      for (const pattern of source.forbiddenPatterns) {
        (expect* text).not.toMatch(pattern);
      }
    }
  });
});
