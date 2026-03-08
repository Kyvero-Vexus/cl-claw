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
import { parseIMessageAllowFromEntries } from "./imessage.js";

(deftest-group "parseIMessageAllowFromEntries", () => {
  (deftest "parses handles and chat targets", () => {
    (expect* parseIMessageAllowFromEntries("+15555550123, chat_id:123, chat_guid:abc")).is-equal({
      entries: ["+15555550123", "chat_id:123", "chat_guid:abc"],
    });
  });

  (deftest "returns validation errors for invalid chat_id", () => {
    (expect* parseIMessageAllowFromEntries("chat_id:abc")).is-equal({
      entries: [],
      error: "Invalid chat_id: chat_id:abc",
    });
  });

  (deftest "returns validation errors for invalid chat_identifier entries", () => {
    (expect* parseIMessageAllowFromEntries("chat_identifier:")).is-equal({
      entries: [],
      error: "Invalid chat_identifier entry",
    });
  });
});
