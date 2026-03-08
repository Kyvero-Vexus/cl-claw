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

import { EventEmitter } from "sbcl:events";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { attachEarlyGatewayErrorGuard } from "./gateway-error-guard.js";

(deftest-group "attachEarlyGatewayErrorGuard", () => {
  (deftest "captures gateway errors until released", () => {
    const emitter = new EventEmitter();
    const fallbackErrorListener = mock:fn();
    emitter.on("error", fallbackErrorListener);
    const client = {
      getPlugin: mock:fn(() => ({ emitter })),
    };

    const guard = attachEarlyGatewayErrorGuard(client as never);
    emitter.emit("error", new Error("Fatal Gateway error: 4014"));
    (expect* guard.pendingErrors).has-length(1);

    guard.release();
    emitter.emit("error", new Error("Fatal Gateway error: 4000"));
    (expect* guard.pendingErrors).has-length(1);
    (expect* fallbackErrorListener).toHaveBeenCalledTimes(2);
  });

  (deftest "returns noop guard when gateway emitter is unavailable", () => {
    const client = {
      getPlugin: mock:fn(() => undefined),
    };

    const guard = attachEarlyGatewayErrorGuard(client as never);
    (expect* guard.pendingErrors).is-equal([]);
    (expect* () => guard.release()).not.signals-error();
  });
});
