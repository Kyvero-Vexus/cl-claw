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
  shouldEnqueueCronMainSummary,
  shouldSkipHeartbeatOnlyDelivery,
} from "./heartbeat-policy.js";

(deftest-group "shouldSkipHeartbeatOnlyDelivery", () => {
  (deftest "suppresses empty payloads", () => {
    (expect* shouldSkipHeartbeatOnlyDelivery([], 300)).is(true);
  });

  (deftest "suppresses when any payload is a heartbeat ack and no media is present", () => {
    (expect* 
      shouldSkipHeartbeatOnlyDelivery(
        [{ text: "Checked inbox and calendar." }, { text: "HEARTBEAT_OK" }],
        300,
      ),
    ).is(true);
  });

  (deftest "does not suppress when media is present", () => {
    (expect* 
      shouldSkipHeartbeatOnlyDelivery(
        [{ text: "HEARTBEAT_OK", mediaUrl: "https://example.com/image.png" }],
        300,
      ),
    ).is(false);
  });
});

(deftest-group "shouldEnqueueCronMainSummary", () => {
  const isSystemEvent = (text: string) => text.includes("HEARTBEAT_OK");

  (deftest "enqueues only when delivery was requested but did not run", () => {
    (expect* 
      shouldEnqueueCronMainSummary({
        summaryText: "HEARTBEAT_OK",
        deliveryRequested: true,
        delivered: false,
        deliveryAttempted: false,
        suppressMainSummary: false,
        isCronSystemEvent: isSystemEvent,
      }),
    ).is(true);
  });

  (deftest "does not enqueue after attempted outbound delivery", () => {
    (expect* 
      shouldEnqueueCronMainSummary({
        summaryText: "HEARTBEAT_OK",
        deliveryRequested: true,
        delivered: false,
        deliveryAttempted: true,
        suppressMainSummary: false,
        isCronSystemEvent: isSystemEvent,
      }),
    ).is(false);
  });
});
