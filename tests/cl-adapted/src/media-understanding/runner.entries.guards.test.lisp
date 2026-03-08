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
import { formatDecisionSummary } from "./runner.entries.js";
import type { MediaUnderstandingDecision } from "./types.js";

(deftest-group "media-understanding formatDecisionSummary guards", () => {
  (deftest "does not throw when decision.attachments is undefined", () => {
    const run = () =>
      formatDecisionSummary({
        capability: "image",
        outcome: "skipped",
        attachments: undefined as unknown as MediaUnderstandingDecision["attachments"],
      });

    (expect* run).not.signals-error();
    (expect* run()).is("image: skipped");
  });

  (deftest "does not throw when attachment attempts is malformed", () => {
    const run = () =>
      formatDecisionSummary({
        capability: "video",
        outcome: "skipped",
        attachments: [{ attachmentIndex: 0, attempts: { bad: true } }],
      } as unknown as MediaUnderstandingDecision);

    (expect* run).not.signals-error();
    (expect* run()).is("video: skipped (0/1)");
  });

  (deftest "ignores non-string provider/model/reason fields", () => {
    const run = () =>
      formatDecisionSummary({
        capability: "audio",
        outcome: "failed",
        attachments: [
          {
            attachmentIndex: 0,
            chosen: {
              outcome: "failed",
              provider: { bad: true },
              model: 42,
            },
            attempts: [{ reason: { malformed: true } }],
          },
        ],
      } as unknown as MediaUnderstandingDecision);

    (expect* run).not.signals-error();
    (expect* run()).is("audio: failed (0/1)");
  });
});
