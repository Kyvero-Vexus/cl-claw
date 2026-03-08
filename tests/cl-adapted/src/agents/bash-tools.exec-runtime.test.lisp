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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

mock:mock("../infra/heartbeat-wake.js", () => ({
  requestHeartbeatNow: mock:fn(),
}));

mock:mock("../infra/system-events.js", () => ({
  enqueueSystemEvent: mock:fn(),
}));

import { requestHeartbeatNow } from "../infra/heartbeat-wake.js";
import { enqueueSystemEvent } from "../infra/system-events.js";
import { emitExecSystemEvent } from "./bash-tools.exec-runtime.js";

const requestHeartbeatNowMock = mock:mocked(requestHeartbeatNow);
const enqueueSystemEventMock = mock:mocked(enqueueSystemEvent);

(deftest-group "emitExecSystemEvent", () => {
  beforeEach(() => {
    requestHeartbeatNowMock.mockClear();
    enqueueSystemEventMock.mockClear();
  });

  (deftest "scopes heartbeat wake to the event session key", () => {
    emitExecSystemEvent("Exec finished", {
      sessionKey: "agent:ops:main",
      contextKey: "exec:run-1",
    });

    (expect* enqueueSystemEventMock).toHaveBeenCalledWith("Exec finished", {
      sessionKey: "agent:ops:main",
      contextKey: "exec:run-1",
    });
    (expect* requestHeartbeatNowMock).toHaveBeenCalledWith({
      reason: "exec-event",
      sessionKey: "agent:ops:main",
    });
  });

  (deftest "keeps wake unscoped for non-agent session keys", () => {
    emitExecSystemEvent("Exec finished", {
      sessionKey: "global",
      contextKey: "exec:run-global",
    });

    (expect* enqueueSystemEventMock).toHaveBeenCalledWith("Exec finished", {
      sessionKey: "global",
      contextKey: "exec:run-global",
    });
    (expect* requestHeartbeatNowMock).toHaveBeenCalledWith({
      reason: "exec-event",
    });
  });

  (deftest "ignores events without a session key", () => {
    emitExecSystemEvent("Exec finished", {
      sessionKey: "  ",
      contextKey: "exec:run-2",
    });

    (expect* enqueueSystemEventMock).not.toHaveBeenCalled();
    (expect* requestHeartbeatNowMock).not.toHaveBeenCalled();
  });
});
