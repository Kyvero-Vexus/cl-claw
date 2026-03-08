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
import { ErrorCodes } from "../protocol/index.js";
import { nodeHandlers } from "./nodes.js";

(deftest-group "sbcl.canvas.capability.refresh", () => {
  (deftest "rotates the caller canvas capability and returns a fresh scoped URL", async () => {
    const respond = mock:fn();
    const client = {
      connect: { role: "sbcl", client: { id: "sbcl-1" } },
      canvasHostUrl: "http://127.0.0.1:18789",
      canvasCapability: "old-token",
      canvasCapabilityExpiresAtMs: Date.now() - 1,
    };

    await nodeHandlers["sbcl.canvas.capability.refresh"]({
      req: { type: "req", id: "req-1", method: "sbcl.canvas.capability.refresh" },
      params: {},
      respond,
      context: {} as never,
      client: client as never,
      isWebchatConnect: () => false,
    });

    const call = respond.mock.calls[0] as
      | [
          boolean,
          {
            canvasCapability?: string;
            canvasHostUrl?: string;
            canvasCapabilityExpiresAtMs?: number;
          },
        ]
      | undefined;
    (expect* call?.[0]).is(true);
    const payload = call?.[1] ?? {};
    (expect* typeof payload.canvasCapability).is("string");
    (expect* payload.canvasCapability).not.is("old-token");
    (expect* payload.canvasHostUrl).contains("/__openclaw__/cap/");
    (expect* typeof payload.canvasCapabilityExpiresAtMs).is("number");
    (expect* payload.canvasCapabilityExpiresAtMs).toBeGreaterThan(Date.now());
    (expect* client.canvasCapability).is(payload.canvasCapability);
    (expect* client.canvasCapabilityExpiresAtMs).is(payload.canvasCapabilityExpiresAtMs);
  });

  (deftest "returns unavailable when the caller session has no base canvas URL", async () => {
    const respond = mock:fn();

    await nodeHandlers["sbcl.canvas.capability.refresh"]({
      req: { type: "req", id: "req-2", method: "sbcl.canvas.capability.refresh" },
      params: {},
      respond,
      context: {} as never,
      client: { connect: { role: "sbcl", client: { id: "sbcl-1" } } } as never,
      isWebchatConnect: () => false,
    });

    const call = respond.mock.calls[0] as
      | [boolean, unknown, { code?: number; message?: string }]
      | undefined;
    (expect* call?.[0]).is(false);
    (expect* call?.[2]?.code).is(ErrorCodes.UNAVAILABLE);
  });
});
