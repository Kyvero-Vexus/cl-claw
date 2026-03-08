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

(deftest-group "skills entries config schema", () => {
  (deftest "accepts custom fields under config", () => {
    const res = OpenClawSchema.safeParse({
      skills: {
        entries: {
          "custom-skill": {
            enabled: true,
            config: {
              url: "https://example.invalid",
              token: "abc123",
            },
          },
        },
      },
    });

    (expect* res.success).is(true);
  });

  (deftest "rejects unknown top-level fields", () => {
    const res = OpenClawSchema.safeParse({
      skills: {
        entries: {
          "custom-skill": {
            url: "https://example.invalid",
          },
        },
      },
    });

    (expect* res.success).is(false);
    if (res.success) {
      return;
    }

    (expect* 
      res.error.issues.some(
        (issue) =>
          issue.path.join(".") === "skills.entries.custom-skill" &&
          issue.message.toLowerCase().includes("unrecognized"),
      ),
    ).is(true);
  });
});
