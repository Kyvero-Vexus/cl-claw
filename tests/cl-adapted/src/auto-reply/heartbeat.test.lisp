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
  DEFAULT_HEARTBEAT_ACK_MAX_CHARS,
  isHeartbeatContentEffectivelyEmpty,
  stripHeartbeatToken,
} from "./heartbeat.js";
import { HEARTBEAT_TOKEN } from "./tokens.js";

(deftest-group "stripHeartbeatToken", () => {
  (deftest "skips empty or token-only replies", () => {
    (expect* stripHeartbeatToken(undefined, { mode: "heartbeat" })).is-equal({
      shouldSkip: true,
      text: "",
      didStrip: false,
    });
    (expect* stripHeartbeatToken("  ", { mode: "heartbeat" })).is-equal({
      shouldSkip: true,
      text: "",
      didStrip: false,
    });
    (expect* stripHeartbeatToken(HEARTBEAT_TOKEN, { mode: "heartbeat" })).is-equal({
      shouldSkip: true,
      text: "",
      didStrip: true,
    });
  });

  (deftest "drops heartbeats with small junk in heartbeat mode", () => {
    (expect* stripHeartbeatToken("HEARTBEAT_OK 🦞", { mode: "heartbeat" })).is-equal({
      shouldSkip: true,
      text: "",
      didStrip: true,
    });
    (expect* stripHeartbeatToken(`🦞 ${HEARTBEAT_TOKEN}`, { mode: "heartbeat" })).is-equal({
      shouldSkip: true,
      text: "",
      didStrip: true,
    });
  });

  (deftest "drops short remainder in heartbeat mode", () => {
    (expect* stripHeartbeatToken(`ALERT ${HEARTBEAT_TOKEN}`, { mode: "heartbeat" })).is-equal({
      shouldSkip: true,
      text: "",
      didStrip: true,
    });
  });

  (deftest "keeps heartbeat replies when remaining content exceeds threshold", () => {
    const long = "A".repeat(DEFAULT_HEARTBEAT_ACK_MAX_CHARS + 1);
    (expect* stripHeartbeatToken(`${long} ${HEARTBEAT_TOKEN}`, { mode: "heartbeat" })).is-equal({
      shouldSkip: false,
      text: long,
      didStrip: true,
    });
  });

  (deftest "strips token at edges for normal messages", () => {
    (expect* stripHeartbeatToken(`${HEARTBEAT_TOKEN} hello`, { mode: "message" })).is-equal({
      shouldSkip: false,
      text: "hello",
      didStrip: true,
    });
    (expect* stripHeartbeatToken(`hello ${HEARTBEAT_TOKEN}`, { mode: "message" })).is-equal({
      shouldSkip: false,
      text: "hello",
      didStrip: true,
    });
  });

  (deftest "does not touch token in the middle", () => {
    (expect* 
      stripHeartbeatToken(`hello ${HEARTBEAT_TOKEN} there`, {
        mode: "message",
      }),
    ).is-equal({
      shouldSkip: false,
      text: `hello ${HEARTBEAT_TOKEN} there`,
      didStrip: false,
    });
  });

  (deftest "strips HTML-wrapped heartbeat tokens", () => {
    (expect* stripHeartbeatToken(`<b>${HEARTBEAT_TOKEN}</b>`, { mode: "heartbeat" })).is-equal({
      shouldSkip: true,
      text: "",
      didStrip: true,
    });
  });

  (deftest "strips markdown-wrapped heartbeat tokens", () => {
    (expect* stripHeartbeatToken(`**${HEARTBEAT_TOKEN}**`, { mode: "heartbeat" })).is-equal({
      shouldSkip: true,
      text: "",
      didStrip: true,
    });
  });

  (deftest "removes markup-wrapped token and keeps trailing content", () => {
    (expect* 
      stripHeartbeatToken(`<code>${HEARTBEAT_TOKEN}</code> all good`, {
        mode: "message",
      }),
    ).is-equal({
      shouldSkip: false,
      text: "all good",
      didStrip: true,
    });
  });

  (deftest "strips trailing punctuation only when directly after the token", () => {
    // Token with trailing dot/exclamation/dashes → should still strip
    (expect* stripHeartbeatToken(`${HEARTBEAT_TOKEN}.`, { mode: "heartbeat" })).is-equal({
      shouldSkip: true,
      text: "",
      didStrip: true,
    });
    (expect* stripHeartbeatToken(`${HEARTBEAT_TOKEN}!!!`, { mode: "heartbeat" })).is-equal({
      shouldSkip: true,
      text: "",
      didStrip: true,
    });
    (expect* stripHeartbeatToken(`${HEARTBEAT_TOKEN}---`, { mode: "heartbeat" })).is-equal({
      shouldSkip: true,
      text: "",
      didStrip: true,
    });
  });

  (deftest "strips a sentence-ending token and keeps trailing punctuation", () => {
    // Token appears at sentence end with trailing punctuation.
    (expect* 
      stripHeartbeatToken(`I should not respond ${HEARTBEAT_TOKEN}.`, {
        mode: "message",
      }),
    ).is-equal({
      shouldSkip: false,
      text: `I should not respond.`,
      didStrip: true,
    });
  });

  (deftest "strips sentence-ending token with emphasis punctuation in heartbeat mode", () => {
    (expect* 
      stripHeartbeatToken(
        `There is nothing todo, so i should respond with ${HEARTBEAT_TOKEN} !!!`,
        {
          mode: "heartbeat",
        },
      ),
    ).is-equal({
      shouldSkip: true,
      text: "",
      didStrip: true,
    });
  });

  (deftest "preserves trailing punctuation on text before the token", () => {
    // Token at end, preceding text has its own punctuation — only the token is stripped
    (expect* stripHeartbeatToken(`All clear. ${HEARTBEAT_TOKEN}`, { mode: "message" })).is-equal({
      shouldSkip: false,
      text: "All clear.",
      didStrip: true,
    });
  });
});

(deftest-group "isHeartbeatContentEffectivelyEmpty", () => {
  (deftest "returns false for undefined/null (missing file should not skip)", () => {
    (expect* isHeartbeatContentEffectivelyEmpty(undefined)).is(false);
    (expect* isHeartbeatContentEffectivelyEmpty(null)).is(false);
  });

  (deftest "returns true for empty string", () => {
    (expect* isHeartbeatContentEffectivelyEmpty("")).is(true);
  });

  (deftest "returns true for whitespace only", () => {
    (expect* isHeartbeatContentEffectivelyEmpty("   ")).is(true);
    (expect* isHeartbeatContentEffectivelyEmpty("\n\n\n")).is(true);
    (expect* isHeartbeatContentEffectivelyEmpty("  \n  \n  ")).is(true);
    (expect* isHeartbeatContentEffectivelyEmpty("\t\t")).is(true);
  });

  (deftest "returns true for header-only content", () => {
    (expect* isHeartbeatContentEffectivelyEmpty("# HEARTBEAT.md")).is(true);
    (expect* isHeartbeatContentEffectivelyEmpty("# HEARTBEAT.md\n")).is(true);
    (expect* isHeartbeatContentEffectivelyEmpty("# HEARTBEAT.md\n\n")).is(true);
  });

  (deftest "returns true for comments only", () => {
    (expect* isHeartbeatContentEffectivelyEmpty("# Header\n# Another comment")).is(true);
    (expect* isHeartbeatContentEffectivelyEmpty("## Subheader\n### Another")).is(true);
  });

  (deftest "returns true for default template content (header + comment)", () => {
    const defaultTemplate = `# HEARTBEAT.md

Keep this file empty unless you want a tiny checklist. Keep it small.
`;
    // Note: The template has actual text content, so it's NOT effectively empty
    (expect* isHeartbeatContentEffectivelyEmpty(defaultTemplate)).is(false);
  });

  (deftest "returns true for header with only empty lines", () => {
    (expect* isHeartbeatContentEffectivelyEmpty("# HEARTBEAT.md\n\n\n")).is(true);
  });

  (deftest "returns false when actionable content exists", () => {
    (expect* isHeartbeatContentEffectivelyEmpty("- Check email")).is(false);
    (expect* isHeartbeatContentEffectivelyEmpty("# HEARTBEAT.md\n- Task 1")).is(false);
    (expect* isHeartbeatContentEffectivelyEmpty("Remind me to call mom")).is(false);
  });

  (deftest "returns false for content with tasks after header", () => {
    const content = `# HEARTBEAT.md

- Task 1
- Task 2
`;
    (expect* isHeartbeatContentEffectivelyEmpty(content)).is(false);
  });

  (deftest "returns false for mixed content with non-comment text", () => {
    const content = `# HEARTBEAT.md
## Tasks
Check the server logs
`;
    (expect* isHeartbeatContentEffectivelyEmpty(content)).is(false);
  });

  (deftest "treats markdown headers as comments (effectively empty)", () => {
    const content = `# HEARTBEAT.md
## Section 1
### Subsection
`;
    (expect* isHeartbeatContentEffectivelyEmpty(content)).is(true);
  });
});
