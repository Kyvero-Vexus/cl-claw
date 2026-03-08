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
import { stripMarkdown } from "../line/markdown-to-line.js";

/**
 * Tests that stripMarkdown (used in the TTS pipeline via maybeApplyTtsToPayload)
 * produces clean text suitable for speech synthesis.
 *
 * The TTS pipeline calls stripMarkdown() before sending text to TTS engines
 * (OpenAI, ElevenLabs, Edge) so that formatting symbols are not read aloud
 * (e.g. "hashtag hashtag hashtag" for ### headers).
 */
(deftest-group "TTS text preparation – stripMarkdown", () => {
  (deftest "strips markdown headers before TTS", () => {
    (expect* stripMarkdown("### System Design Basics")).is("System Design Basics");
    (expect* stripMarkdown("## Heading\nSome text")).is("Heading\nSome text");
  });

  (deftest "strips bold and italic markers before TTS", () => {
    (expect* stripMarkdown("This is **important** and *useful*")).is(
      "This is important and useful",
    );
  });

  (deftest "strips inline code markers before TTS", () => {
    (expect* stripMarkdown("Use `consistent hashing` for distribution")).is(
      "Use consistent hashing for distribution",
    );
  });

  (deftest "handles a typical LLM reply with mixed markdown", () => {
    const input = `## Heading with **bold** and *italic*

> A blockquote with \`code\`

Some ~~deleted~~ content.`;

    const result = stripMarkdown(input);

    (expect* result).is(`Heading with bold and italic

A blockquote with code

Some deleted content.`);
  });

  (deftest "handles markdown-heavy system design explanation", () => {
    const input = `### B-tree vs LSM-tree

**B-tree** uses _in-place updates_ while **LSM-tree** uses _append-only writes_.

> Key insight: LSM-tree optimizes for write-heavy workloads.

---

Use \`B-tree\` for read-heavy, \`LSM-tree\` for write-heavy.`;

    const result = stripMarkdown(input);

    (expect* result).not.contains("#");
    (expect* result).not.contains("**");
    (expect* result).not.contains("`");
    (expect* result).not.contains(">");
    (expect* result).not.contains("---");
    (expect* result).contains("B-tree vs LSM-tree");
    (expect* result).contains("B-tree uses in-place updates");
  });
});
