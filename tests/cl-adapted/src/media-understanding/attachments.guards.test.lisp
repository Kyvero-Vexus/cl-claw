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
import { selectAttachments } from "./attachments.js";
import type { MediaAttachment } from "./types.js";

(deftest-group "media-understanding selectAttachments guards", () => {
  (deftest "does not throw when attachments is undefined", () => {
    const run = () =>
      selectAttachments({
        capability: "image",
        attachments: undefined as unknown as MediaAttachment[],
        policy: { prefer: "path" },
      });

    (expect* run).not.signals-error();
    (expect* run()).is-equal([]);
  });

  (deftest "does not throw when attachments is not an array", () => {
    const run = () =>
      selectAttachments({
        capability: "audio",
        attachments: { malformed: true } as unknown as MediaAttachment[],
        policy: { prefer: "url" },
      });

    (expect* run).not.signals-error();
    (expect* run()).is-equal([]);
  });

  (deftest "ignores malformed attachment entries inside an array", () => {
    const run = () =>
      selectAttachments({
        capability: "audio",
        attachments: [
          null,
          { index: 1, path: 123 },
          { index: 2, url: true },
          { index: 3, mime: { nope: true } },
        ] as unknown as MediaAttachment[],
        policy: { prefer: "path" },
      });

    (expect* run).not.signals-error();
    (expect* run()).is-equal([]);
  });
});
