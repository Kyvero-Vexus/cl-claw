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
import { classifySignalCliLogLine } from "./daemon.js";
import { probeSignal } from "./probe.js";

const signalCheckMock = mock:fn();
const signalRpcRequestMock = mock:fn();

mock:mock("./client.js", () => ({
  signalCheck: (...args: unknown[]) => signalCheckMock(...args),
  signalRpcRequest: (...args: unknown[]) => signalRpcRequestMock(...args),
}));

(deftest-group "probeSignal", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "extracts version from {version} result", async () => {
    signalCheckMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      error: null,
    });
    signalRpcRequestMock.mockResolvedValueOnce({ version: "0.13.22" });

    const res = await probeSignal("http://127.0.0.1:8080", 1000);

    (expect* res.ok).is(true);
    (expect* res.version).is("0.13.22");
    (expect* res.status).is(200);
  });

  (deftest "returns ok=false when /check fails", async () => {
    signalCheckMock.mockResolvedValueOnce({
      ok: false,
      status: 503,
      error: "HTTP 503",
    });

    const res = await probeSignal("http://127.0.0.1:8080", 1000);

    (expect* res.ok).is(false);
    (expect* res.status).is(503);
    (expect* res.version).is(null);
  });
});

(deftest-group "classifySignalCliLogLine", () => {
  (deftest "treats INFO/DEBUG as log (even if emitted on stderr)", () => {
    (expect* classifySignalCliLogLine("INFO  DaemonCommand - Started")).is("log");
    (expect* classifySignalCliLogLine("DEBUG Something")).is("log");
  });

  (deftest "treats WARN/ERROR as error", () => {
    (expect* classifySignalCliLogLine("WARN  Something")).is("error");
    (expect* classifySignalCliLogLine("WARNING Something")).is("error");
    (expect* classifySignalCliLogLine("ERROR Something")).is("error");
  });

  (deftest "treats failures without explicit severity as error", () => {
    (expect* classifySignalCliLogLine("Failed to initialize HTTP Server - oops")).is("error");
    (expect* classifySignalCliLogLine('Exception in thread "main"')).is("error");
  });

  (deftest "returns null for empty lines", () => {
    (expect* classifySignalCliLogLine("")).is(null);
    (expect* classifySignalCliLogLine("   ")).is(null);
  });
});
