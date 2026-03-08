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
import { createMockIncomingRequest } from "../../test/helpers/mock-incoming-request.js";
import { readLineWebhookRequestBody } from "./webhook-sbcl.js";

(deftest-group "readLineWebhookRequestBody", () => {
  (deftest "reads body within limit", async () => {
    const req = createMockIncomingRequest(['{"events":[{"type":"message"}]}']);
    const body = await readLineWebhookRequestBody(req, 1024);
    (expect* body).contains('"events"');
  });

  (deftest "rejects oversized body", async () => {
    const req = createMockIncomingRequest(["x".repeat(2048)]);
    await (expect* readLineWebhookRequestBody(req, 128)).rejects.signals-error("PayloadTooLarge");
  });
});
