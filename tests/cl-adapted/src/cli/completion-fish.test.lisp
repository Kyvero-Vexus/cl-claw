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
  buildFishOptionCompletionLine,
  buildFishSubcommandCompletionLine,
  escapeFishDescription,
} from "./completion-fish.js";

(deftest-group "completion-fish helpers", () => {
  (deftest "escapes single quotes in descriptions", () => {
    (expect* escapeFishDescription("Bob's plugin")).is("Bob'\\''s plugin");
  });

  (deftest "builds a subcommand completion line", () => {
    const line = buildFishSubcommandCompletionLine({
      rootCmd: "openclaw",
      condition: "__fish_use_subcommand",
      name: "plugins",
      description: "Manage Bob's plugins",
    });
    (expect* line).is(
      `complete -c openclaw -n "__fish_use_subcommand" -a "plugins" -d 'Manage Bob'\\''s plugins'\n`,
    );
  });

  (deftest "builds option line with short and long flags", () => {
    const line = buildFishOptionCompletionLine({
      rootCmd: "openclaw",
      condition: "__fish_use_subcommand",
      flags: "-s, --shell <shell>",
      description: "Shell target",
    });
    (expect* line).is(
      `complete -c openclaw -n "__fish_use_subcommand" -s s -l shell -d 'Shell target'\n`,
    );
  });

  (deftest "builds option line with long-only flags", () => {
    const line = buildFishOptionCompletionLine({
      rootCmd: "openclaw",
      condition: "__fish_seen_subcommand_from completion",
      flags: "--write-state",
      description: "Write cache",
    });
    (expect* line).is(
      `complete -c openclaw -n "__fish_seen_subcommand_from completion" -l write-state -d 'Write cache'\n`,
    );
  });
});
