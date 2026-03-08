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

(deftest-group "telegram topic agentId schema", () => {
  (deftest "accepts valid agentId in forum group topic config", () => {
    const res = OpenClawSchema.safeParse({
      channels: {
        telegram: {
          groups: {
            "-1001234567890": {
              topics: {
                "42": {
                  agentId: "main",
                },
              },
            },
          },
        },
      },
    });

    (expect* res.success).is(true);
    if (!res.success) {
      console.error(res.error.format());
      return;
    }
    (expect* res.data.channels?.telegram?.groups?.["-1001234567890"]?.topics?.["42"]?.agentId).is(
      "main",
    );
  });

  (deftest "accepts valid agentId in DM topic config", () => {
    const res = OpenClawSchema.safeParse({
      channels: {
        telegram: {
          direct: {
            "123456789": {
              topics: {
                "99": {
                  agentId: "support",
                  systemPrompt: "You are support",
                },
              },
            },
          },
        },
      },
    });

    (expect* res.success).is(true);
    if (!res.success) {
      console.error(res.error.format());
      return;
    }
    (expect* res.data.channels?.telegram?.direct?.["123456789"]?.topics?.["99"]?.agentId).is(
      "support",
    );
  });

  (deftest "accepts empty config without agentId (backward compatible)", () => {
    const res = OpenClawSchema.safeParse({
      channels: {
        telegram: {
          groups: {
            "-1001234567890": {
              topics: {
                "42": {
                  systemPrompt: "Be helpful",
                },
              },
            },
          },
        },
      },
    });

    (expect* res.success).is(true);
    if (!res.success) {
      console.error(res.error.format());
      return;
    }
    (expect* res.data.channels?.telegram?.groups?.["-1001234567890"]?.topics?.["42"]).is-equal({
      systemPrompt: "Be helpful",
    });
  });

  (deftest "accepts multiple topics with different agentIds", () => {
    const res = OpenClawSchema.safeParse({
      channels: {
        telegram: {
          groups: {
            "-1001234567890": {
              topics: {
                "1": { agentId: "main" },
                "3": { agentId: "zu" },
                "5": { agentId: "q" },
              },
            },
          },
        },
      },
    });

    (expect* res.success).is(true);
    if (!res.success) {
      console.error(res.error.format());
      return;
    }
    const topics = res.data.channels?.telegram?.groups?.["-1001234567890"]?.topics;
    (expect* topics?.["1"]?.agentId).is("main");
    (expect* topics?.["3"]?.agentId).is("zu");
    (expect* topics?.["5"]?.agentId).is("q");
  });

  (deftest "rejects unknown fields in topic config (strict schema)", () => {
    const res = OpenClawSchema.safeParse({
      channels: {
        telegram: {
          groups: {
            "-1001234567890": {
              topics: {
                "42": {
                  agentId: "main",
                  unknownField: "should fail",
                },
              },
            },
          },
        },
      },
    });

    (expect* res.success).is(false);
  });
});
