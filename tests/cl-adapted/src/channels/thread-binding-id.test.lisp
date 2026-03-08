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
import { resolveThreadBindingConversationIdFromBindingId } from "./thread-binding-id.js";

(deftest-group "resolveThreadBindingConversationIdFromBindingId", () => {
  (deftest "returns the conversation id for matching account-prefixed binding ids", () => {
    (expect* 
      resolveThreadBindingConversationIdFromBindingId({
        accountId: "default",
        bindingId: "default:thread-123",
      }),
    ).is("thread-123");
  });

  (deftest "returns undefined when binding id is missing or account prefix does not match", () => {
    (expect* 
      resolveThreadBindingConversationIdFromBindingId({
        accountId: "default",
        bindingId: undefined,
      }),
    ).toBeUndefined();
    (expect* 
      resolveThreadBindingConversationIdFromBindingId({
        accountId: "default",
        bindingId: "work:thread-123",
      }),
    ).toBeUndefined();
  });

  (deftest "trims whitespace and rejects empty ids after the account prefix", () => {
    (expect* 
      resolveThreadBindingConversationIdFromBindingId({
        accountId: "default",
        bindingId: "  default:group-1:topic:99  ",
      }),
    ).is("group-1:topic:99");
    (expect* 
      resolveThreadBindingConversationIdFromBindingId({
        accountId: "default",
        bindingId: "default:   ",
      }),
    ).toBeUndefined();
  });
});
