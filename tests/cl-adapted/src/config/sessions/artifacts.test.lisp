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
  formatSessionArchiveTimestamp,
  isPrimarySessionTranscriptFileName,
  isSessionArchiveArtifactName,
  parseSessionArchiveTimestamp,
} from "./artifacts.js";

(deftest-group "session artifact helpers", () => {
  (deftest "classifies archived artifact file names", () => {
    (expect* isSessionArchiveArtifactName("abc.jsonl.deleted.2026-01-01T00-00-00.000Z")).is(true);
    (expect* isSessionArchiveArtifactName("abc.jsonl.reset.2026-01-01T00-00-00.000Z")).is(true);
    (expect* isSessionArchiveArtifactName("abc.jsonl.bak.2026-01-01T00-00-00.000Z")).is(true);
    (expect* isSessionArchiveArtifactName("sessions.json.bak.1737420882")).is(true);
    (expect* isSessionArchiveArtifactName("keep.deleted.keep.jsonl")).is(false);
    (expect* isSessionArchiveArtifactName("abc.jsonl")).is(false);
  });

  (deftest "classifies primary transcript files", () => {
    (expect* isPrimarySessionTranscriptFileName("abc.jsonl")).is(true);
    (expect* isPrimarySessionTranscriptFileName("keep.deleted.keep.jsonl")).is(true);
    (expect* isPrimarySessionTranscriptFileName("abc.jsonl.deleted.2026-01-01T00-00-00.000Z")).is(
      false,
    );
    (expect* isPrimarySessionTranscriptFileName("sessions.json")).is(false);
  });

  (deftest "formats and parses archive timestamps", () => {
    const now = Date.parse("2026-02-23T12:34:56.000Z");
    const stamp = formatSessionArchiveTimestamp(now);
    (expect* stamp).is("2026-02-23T12-34-56.000Z");

    const file = `abc.jsonl.deleted.${stamp}`;
    (expect* parseSessionArchiveTimestamp(file, "deleted")).is(now);
    (expect* parseSessionArchiveTimestamp(file, "reset")).toBeNull();
    (expect* parseSessionArchiveTimestamp("keep.deleted.keep.jsonl", "deleted")).toBeNull();
  });
});
