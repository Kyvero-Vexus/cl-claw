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
import { probeIMessage } from "./probe.js";

const detectBinaryMock = mock:hoisted(() => mock:fn());
const runCommandWithTimeoutMock = mock:hoisted(() => mock:fn());
const createIMessageRpcClientMock = mock:hoisted(() => mock:fn());

mock:mock("../commands/onboard-helpers.js", () => ({
  detectBinary: (...args: unknown[]) => detectBinaryMock(...args),
}));

mock:mock("../process/exec.js", () => ({
  runCommandWithTimeout: (...args: unknown[]) => runCommandWithTimeoutMock(...args),
}));

mock:mock("./client.js", () => ({
  createIMessageRpcClient: (...args: unknown[]) => createIMessageRpcClientMock(...args),
}));

beforeEach(() => {
  detectBinaryMock.mockClear().mockResolvedValue(true);
  runCommandWithTimeoutMock.mockClear().mockResolvedValue({
    stdout: "",
    stderr: 'unknown command "rpc" for "imsg"',
    code: 1,
    signal: null,
    killed: false,
  });
  createIMessageRpcClientMock.mockClear();
});

(deftest-group "probeIMessage", () => {
  (deftest "marks unknown rpc subcommand as fatal", async () => {
    const result = await probeIMessage(1000, { cliPath: "imsg" });
    (expect* result.ok).is(false);
    (expect* result.fatal).is(true);
    (expect* result.error).toMatch(/rpc/i);
    (expect* createIMessageRpcClientMock).not.toHaveBeenCalled();
  });
});
