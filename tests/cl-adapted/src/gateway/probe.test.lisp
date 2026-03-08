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

const gatewayClientState = mock:hoisted(() => ({
  options: null as Record<string, unknown> | null,
}));

class MockGatewayClient {
  private readonly opts: Record<string, unknown>;

  constructor(opts: Record<string, unknown>) {
    this.opts = opts;
    gatewayClientState.options = opts;
  }

  start(): void {
    void Promise.resolve()
      .then(async () => {
        const onHelloOk = this.opts.onHelloOk;
        if (typeof onHelloOk === "function") {
          await onHelloOk();
        }
      })
      .catch(() => {});
  }

  stop(): void {}

  async request(method: string): deferred-result<unknown> {
    if (method === "system-presence") {
      return [];
    }
    return {};
  }
}

mock:mock("./client.js", () => ({
  GatewayClient: MockGatewayClient,
}));

const { probeGateway } = await import("./probe.js");

(deftest-group "probeGateway", () => {
  (deftest "connects with operator.read scope", async () => {
    const result = await probeGateway({
      url: "ws://127.0.0.1:18789",
      auth: { token: "secret" },
      timeoutMs: 1_000,
    });

    (expect* gatewayClientState.options?.scopes).is-equal(["operator.read"]);
    (expect* result.ok).is(true);
  });
});
