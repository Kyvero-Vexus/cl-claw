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
import { validateConfigObject } from "./validation.js";

// NOTE: These tests ensure allow + alsoAllow cannot be set in the same scope.

(deftest-group "config: tools.alsoAllow", () => {
  (deftest "rejects tools.allow + tools.alsoAllow together", () => {
    const res = validateConfigObject({
      tools: {
        allow: ["group:fs"],
        alsoAllow: ["lobster"],
      },
    });

    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues.some((i) => i.path === "tools")).is(true);
    }
  });

  (deftest "rejects agents.list[].tools.allow + alsoAllow together", () => {
    const res = validateConfigObject({
      agents: {
        list: [
          {
            id: "main",
            tools: {
              allow: ["group:fs"],
              alsoAllow: ["lobster"],
            },
          },
        ],
      },
    });

    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues.some((i) => i.path.includes("agents.list"))).is(true);
    }
  });

  (deftest "allows profile + alsoAllow", () => {
    const res = validateConfigObject({
      tools: {
        profile: "coding",
        alsoAllow: ["lobster"],
      },
    });

    (expect* res.ok).is(true);
  });
});
