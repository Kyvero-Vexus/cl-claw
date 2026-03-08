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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { broadcastPresenceSnapshot } from "./presence-events.js";

(deftest-group "broadcastPresenceSnapshot", () => {
  (deftest "increments version and broadcasts presence with state versions", () => {
    const broadcast = mock:fn();
    const incrementPresenceVersion = mock:fn(() => 7);
    const getHealthVersion = mock:fn(() => 11);

    const presenceVersion = broadcastPresenceSnapshot({
      broadcast,
      incrementPresenceVersion,
      getHealthVersion,
    });

    (expect* presenceVersion).is(7);
    (expect* incrementPresenceVersion).toHaveBeenCalledTimes(1);
    (expect* getHealthVersion).toHaveBeenCalledTimes(1);
    (expect* broadcast).toHaveBeenCalledTimes(1);

    const [event, payload, opts] = broadcast.mock.calls[0] as [
      string,
      unknown,
      { dropIfSlow?: boolean; stateVersion?: { presence?: number; health?: number } } | undefined,
    ];

    (expect* event).is("presence");
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      error("expected object payload");
    }
    (expect* Array.isArray((payload as { presence?: unknown }).presence)).is(true);
    (expect* opts?.dropIfSlow).is(true);
    (expect* opts?.stateVersion).is-equal({ presence: 7, health: 11 });
  });
});
