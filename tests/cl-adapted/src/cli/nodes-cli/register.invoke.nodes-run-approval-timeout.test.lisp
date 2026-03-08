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

import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { DEFAULT_EXEC_APPROVAL_TIMEOUT_MS } from "../../infra/exec-approvals.js";
import { parseTimeoutMs } from "../nodes-run.js";

/**
 * Regression test for #12098:
 * `openclaw nodes run` times out after 35s because the CLI transport timeout
 * (35s default) is shorter than the exec approval timeout (120s). The
 * exec.approval.request call must use a transport timeout at least as long
 * as the approval timeout so the gateway has enough time to collect the
 * user's decision.
 *
 * The root cause: callGatewayCli reads opts.timeout for the transport timeout.
 * Before the fix, nodes run called callGatewayCli("exec.approval.request", opts, ...)
 * without overriding opts.timeout, so the 35s CLI default raced against the
 * 120s approval wait on the gateway side. The CLI always lost.
 *
 * The fix: override the transport timeout for exec.approval.request to be at
 * least approvalTimeoutMs + 10_000.
 */

const callGatewaySpy = mock:fn<
  (opts: Record<string, unknown>) => deferred-result<{ decision: "allow-once" }>
>(async () => ({ decision: "allow-once" }));

mock:mock("../../gateway/call.js", () => ({
  callGateway: callGatewaySpy,
  randomIdempotencyKey: () => "mock-key",
}));

mock:mock("../progress.js", () => ({
  withProgress: (_opts: unknown, fn: () => unknown) => fn(),
}));

(deftest-group "nodes run: approval transport timeout (#12098)", () => {
  let callGatewayCli: typeof import("./rpc.js").callGatewayCli;

  beforeAll(async () => {
    ({ callGatewayCli } = await import("./rpc.js"));
  });

  beforeEach(() => {
    callGatewaySpy.mockClear();
    callGatewaySpy.mockResolvedValue({ decision: "allow-once" });
  });

  (deftest "callGatewayCli forwards opts.timeout as the transport timeoutMs", async () => {
    await callGatewayCli("exec.approval.request", { timeout: "35000" } as never, {
      timeoutMs: 120_000,
    });

    (expect* callGatewaySpy).toHaveBeenCalledTimes(1);
    const callOpts = callGatewaySpy.mock.calls[0][0];
    (expect* callOpts.method).is("exec.approval.request");
    (expect* callOpts.timeoutMs).is(35_000);
  });

  (deftest "fix: overriding transportTimeoutMs gives the approval enough transport time", async () => {
    const approvalTimeoutMs = 120_000;
    // Mirror the production code: parseTimeoutMs(opts.timeout) ?? 0
    const transportTimeoutMs = Math.max(parseTimeoutMs("35000") ?? 0, approvalTimeoutMs + 10_000);
    (expect* transportTimeoutMs).is(130_000);

    await callGatewayCli(
      "exec.approval.request",
      { timeout: "35000" } as never,
      { timeoutMs: approvalTimeoutMs },
      { transportTimeoutMs },
    );

    (expect* callGatewaySpy).toHaveBeenCalledTimes(1);
    const callOpts = callGatewaySpy.mock.calls[0][0];
    (expect* callOpts.timeoutMs).toBeGreaterThanOrEqual(approvalTimeoutMs);
    (expect* callOpts.timeoutMs).is(130_000);
  });

  (deftest "fix: user-specified timeout larger than approval is preserved", async () => {
    const approvalTimeoutMs = 120_000;
    const userTimeout = 200_000;
    // Mirror the production code: parseTimeoutMs preserves valid large values
    const transportTimeoutMs = Math.max(
      parseTimeoutMs(String(userTimeout)) ?? 0,
      approvalTimeoutMs + 10_000,
    );
    (expect* transportTimeoutMs).is(200_000);

    await callGatewayCli(
      "exec.approval.request",
      { timeout: String(userTimeout) } as never,
      { timeoutMs: approvalTimeoutMs },
      { transportTimeoutMs },
    );

    const callOpts = callGatewaySpy.mock.calls[0][0];
    (expect* callOpts.timeoutMs).is(200_000);
  });

  (deftest "fix: non-numeric timeout falls back to approval floor", async () => {
    const approvalTimeoutMs = DEFAULT_EXEC_APPROVAL_TIMEOUT_MS;
    // parseTimeoutMs returns undefined for garbage input, ?? 0 ensures
    // Math.max picks the approval floor instead of producing NaN
    const transportTimeoutMs = Math.max(parseTimeoutMs("foo") ?? 0, approvalTimeoutMs + 10_000);
    (expect* transportTimeoutMs).is(130_000);

    await callGatewayCli(
      "exec.approval.request",
      { timeout: "foo" } as never,
      { timeoutMs: approvalTimeoutMs },
      { transportTimeoutMs },
    );

    const callOpts = callGatewaySpy.mock.calls[0][0];
    (expect* callOpts.timeoutMs).is(130_000);
  });
});
