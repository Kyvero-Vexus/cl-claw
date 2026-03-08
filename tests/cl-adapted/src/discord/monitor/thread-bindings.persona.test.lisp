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
  resolveThreadBindingPersona,
  resolveThreadBindingPersonaFromRecord,
} from "./thread-bindings.persona.js";
import type { ThreadBindingRecord } from "./thread-bindings.types.js";

(deftest-group "thread binding persona", () => {
  (deftest "prefers explicit label and prefixes with gear", () => {
    (expect* resolveThreadBindingPersona({ label: "codex thread", agentId: "codex" })).is(
      "⚙️ codex thread",
    );
  });

  (deftest "falls back to agent id when label is missing", () => {
    (expect* resolveThreadBindingPersona({ agentId: "codex" })).is("⚙️ codex");
  });

  (deftest "builds persona from binding record", () => {
    const record = {
      accountId: "default",
      channelId: "parent-1",
      threadId: "thread-1",
      targetKind: "acp",
      targetSessionKey: "agent:codex:acp:session-1",
      agentId: "codex",
      boundBy: "system",
      boundAt: Date.now(),
      lastActivityAt: Date.now(),
      label: "codex-thread",
    } satisfies ThreadBindingRecord;
    (expect* resolveThreadBindingPersonaFromRecord(record)).is("⚙️ codex-thread");
  });
});
