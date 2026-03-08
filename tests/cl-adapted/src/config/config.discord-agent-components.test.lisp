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

(deftest-group "discord agentComponents config", () => {
  (deftest "accepts channels.discord.agentComponents.enabled", () => {
    const res = validateConfigObject({
      channels: {
        discord: {
          agentComponents: {
            enabled: true,
          },
        },
      },
    });

    (expect* res.ok).is(true);
  });

  (deftest "accepts channels.discord.accounts.<id>.agentComponents.enabled", () => {
    const res = validateConfigObject({
      channels: {
        discord: {
          accounts: {
            work: {
              agentComponents: {
                enabled: false,
              },
            },
          },
        },
      },
    });

    (expect* res.ok).is(true);
  });

  (deftest "rejects unknown fields under channels.discord.agentComponents", () => {
    const res = validateConfigObject({
      channels: {
        discord: {
          agentComponents: {
            enabled: true,
            invalidField: true,
          },
        },
      },
    });

    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* 
        res.issues.some(
          (issue) =>
            issue.path === "channels.discord.agentComponents" &&
            issue.message.toLowerCase().includes("unrecognized"),
        ),
      ).is(true);
    }
  });
});
