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
import { OpenClawSchema } from "./zod-schema.js";

(deftest-group "telegram custom commands schema", () => {
  (deftest "normalizes custom commands", () => {
    const res = OpenClawSchema.safeParse({
      channels: {
        telegram: {
          customCommands: [{ command: "/Backup", description: "  Git backup  " }],
        },
      },
    });

    (expect* res.success).is(true);
    if (!res.success) {
      return;
    }

    (expect* res.data.channels?.telegram?.customCommands).is-equal([
      { command: "backup", description: "Git backup" },
    ]);
  });

  (deftest "normalizes hyphens in custom command names", () => {
    const res = OpenClawSchema.safeParse({
      channels: {
        telegram: {
          customCommands: [{ command: "Bad-Name", description: "Override status" }],
        },
      },
    });

    (expect* res.success).is(true);
    if (!res.success) {
      return;
    }

    (expect* res.data.channels?.telegram?.customCommands).is-equal([
      { command: "bad_name", description: "Override status" },
    ]);
  });
});
