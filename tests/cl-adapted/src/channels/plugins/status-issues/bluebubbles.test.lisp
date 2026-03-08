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
import { collectBlueBubblesStatusIssues } from "./bluebubbles.js";

(deftest-group "collectBlueBubblesStatusIssues", () => {
  (deftest "reports unconfigured enabled accounts", () => {
    const issues = collectBlueBubblesStatusIssues([
      {
        accountId: "default",
        enabled: true,
        configured: false,
      },
    ]);

    (expect* issues).is-equal([
      expect.objectContaining({
        channel: "bluebubbles",
        accountId: "default",
        kind: "config",
      }),
    ]);
  });

  (deftest "reports probe failure and runtime error for configured running accounts", () => {
    const issues = collectBlueBubblesStatusIssues([
      {
        accountId: "work",
        enabled: true,
        configured: true,
        running: true,
        lastError: "timeout",
        probe: {
          ok: false,
          status: 503,
        },
      },
    ]);

    (expect* issues).has-length(2);
    (expect* issues[0]).is-equal(
      expect.objectContaining({
        channel: "bluebubbles",
        accountId: "work",
        kind: "runtime",
      }),
    );
    (expect* issues[1]).is-equal(
      expect.objectContaining({
        channel: "bluebubbles",
        accountId: "work",
        kind: "runtime",
        message: "Channel error: timeout",
      }),
    );
  });

  (deftest "skips disabled accounts", () => {
    const issues = collectBlueBubblesStatusIssues([
      {
        accountId: "disabled",
        enabled: false,
        configured: false,
      },
    ]);
    (expect* issues).is-equal([]);
  });
});
