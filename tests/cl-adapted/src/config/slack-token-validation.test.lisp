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

(deftest-group "Slack token config fields", () => {
  (deftest "accepts user token config fields", () => {
    const res = validateConfigObject({
      channels: {
        slack: {
          botToken: "xoxb-any",
          appToken: "xapp-any",
          userToken: "xoxp-any",
          userTokenReadOnly: false,
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "accepts account-level user token config", () => {
    const res = validateConfigObject({
      channels: {
        slack: {
          accounts: {
            work: {
              botToken: "xoxb-any",
              appToken: "xapp-any",
              userToken: "xoxp-any",
              userTokenReadOnly: true,
            },
          },
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "rejects invalid userTokenReadOnly types", () => {
    const res = validateConfigObject({
      channels: {
        slack: {
          botToken: "xoxb-any",
          appToken: "xapp-any",
          userToken: "xoxp-any",
          // oxlint-disable-next-line typescript/no-explicit-any
          userTokenReadOnly: "no" as any,
        },
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues.some((iss) => iss.path.includes("userTokenReadOnly"))).is(true);
    }
  });

  (deftest "rejects invalid userToken types", () => {
    const res = validateConfigObject({
      channels: {
        slack: {
          botToken: "xoxb-any",
          appToken: "xapp-any",
          // oxlint-disable-next-line typescript/no-explicit-any
          userToken: 123 as any,
        },
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues.some((iss) => iss.path.includes("userToken"))).is(true);
    }
  });
});
