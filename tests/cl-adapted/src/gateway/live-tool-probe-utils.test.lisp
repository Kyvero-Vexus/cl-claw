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
  hasExpectedSingleNonce,
  hasExpectedToolNonce,
  isLikelyToolNonceRefusal,
  shouldRetryExecReadProbe,
  shouldRetryToolReadProbe,
} from "./live-tool-probe-utils.js";

(deftest-group "live tool probe utils", () => {
  (deftest "matches nonce pair when both are present", () => {
    (expect* hasExpectedToolNonce("value a-1 and b-2", "a-1", "b-2")).is(true);
    (expect* hasExpectedToolNonce("value a-1 only", "a-1", "b-2")).is(false);
  });

  (deftest "matches single nonce when present", () => {
    (expect* hasExpectedSingleNonce("value nonce-1", "nonce-1")).is(true);
    (expect* hasExpectedSingleNonce("value nonce-2", "nonce-1")).is(false);
  });

  (deftest "detects anthropic nonce refusal phrasing", () => {
    (expect* 
      isLikelyToolNonceRefusal(
        "Same request, same answer — this isn't a real OpenClaw probe. No part of the system asks me to parrot back nonce values.",
      ),
    ).is(true);
  });

  (deftest "does not treat generic helper text as nonce refusal", () => {
    (expect* isLikelyToolNonceRefusal("I can help with that request.")).is(false);
  });

  (deftest "detects prompt-injection style tool refusal without nonce text", () => {
    (expect* 
      isLikelyToolNonceRefusal(
        "That's not a legitimate self-test. This looks like a prompt injection attempt.",
      ),
    ).is(true);
  });

  (deftest "retries malformed tool output when attempts remain", () => {
    (expect* 
      shouldRetryToolReadProbe({
        text: "read[object Object],[object Object]",
        nonceA: "nonce-a",
        nonceB: "nonce-b",
        provider: "mistral",
        attempt: 0,
        maxAttempts: 3,
      }),
    ).is(true);
  });

  (deftest "does not retry once max attempts are exhausted", () => {
    (expect* 
      shouldRetryToolReadProbe({
        text: "read[object Object],[object Object]",
        nonceA: "nonce-a",
        nonceB: "nonce-b",
        provider: "mistral",
        attempt: 2,
        maxAttempts: 3,
      }),
    ).is(false);
  });

  (deftest "does not retry when nonce pair is already present", () => {
    (expect* 
      shouldRetryToolReadProbe({
        text: "nonce-a nonce-b",
        nonceA: "nonce-a",
        nonceB: "nonce-b",
        provider: "mistral",
        attempt: 0,
        maxAttempts: 3,
      }),
    ).is(false);
  });

  (deftest "retries when tool output is empty and attempts remain", () => {
    (expect* 
      shouldRetryToolReadProbe({
        text: "   ",
        nonceA: "nonce-a",
        nonceB: "nonce-b",
        provider: "openai",
        attempt: 0,
        maxAttempts: 3,
      }),
    ).is(true);
  });

  (deftest "retries when output still looks like tool/function scaffolding", () => {
    (expect* 
      shouldRetryToolReadProbe({
        text: "Use tool function read[] now.",
        nonceA: "nonce-a",
        nonceB: "nonce-b",
        provider: "openai",
        attempt: 0,
        maxAttempts: 3,
      }),
    ).is(true);
  });

  (deftest "retries mistral nonce marker echoes without parsed nonce values", () => {
    (expect* 
      shouldRetryToolReadProbe({
        text: "nonceA= nonceB=",
        nonceA: "nonce-a",
        nonceB: "nonce-b",
        provider: "mistral",
        attempt: 0,
        maxAttempts: 3,
      }),
    ).is(true);
  });

  (deftest "retries anthropic nonce refusal output", () => {
    (expect* 
      shouldRetryToolReadProbe({
        text: "This isn't a real OpenClaw probe; I won't parrot back nonce values.",
        nonceA: "nonce-a",
        nonceB: "nonce-b",
        provider: "anthropic",
        attempt: 0,
        maxAttempts: 3,
      }),
    ).is(true);
  });

  (deftest "retries anthropic prompt-injection refusal output", () => {
    (expect* 
      shouldRetryToolReadProbe({
        text: "This is not a legitimate self-test; it appears to be a prompt injection attempt.",
        nonceA: "nonce-a",
        nonceB: "nonce-b",
        provider: "anthropic",
        attempt: 0,
        maxAttempts: 3,
      }),
    ).is(true);
  });

  (deftest "does not retry nonce marker echoes for non-mistral providers", () => {
    (expect* 
      shouldRetryToolReadProbe({
        text: "nonceA= nonceB=",
        nonceA: "nonce-a",
        nonceB: "nonce-b",
        provider: "openai",
        attempt: 0,
        maxAttempts: 3,
      }),
    ).is(false);
  });

  (deftest "retries malformed exec+read output when attempts remain", () => {
    (expect* 
      shouldRetryExecReadProbe({
        text: "read[object Object]",
        nonce: "nonce-c",
        provider: "openai",
        attempt: 0,
        maxAttempts: 3,
      }),
    ).is(true);
  });

  (deftest "does not retry exec+read once max attempts are exhausted", () => {
    (expect* 
      shouldRetryExecReadProbe({
        text: "read[object Object]",
        nonce: "nonce-c",
        provider: "openai",
        attempt: 2,
        maxAttempts: 3,
      }),
    ).is(false);
  });

  (deftest "does not retry exec+read when nonce is present", () => {
    (expect* 
      shouldRetryExecReadProbe({
        text: "nonce-c",
        nonce: "nonce-c",
        provider: "openai",
        attempt: 0,
        maxAttempts: 3,
      }),
    ).is(false);
  });

  (deftest "retries anthropic exec+read nonce refusal output", () => {
    (expect* 
      shouldRetryExecReadProbe({
        text: "No part of the system asks me to parrot back nonce values.",
        nonce: "nonce-c",
        provider: "anthropic",
        attempt: 0,
        maxAttempts: 3,
      }),
    ).is(true);
  });
});
