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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";

const mocks = mock:hoisted(() => ({
  resolveSystemNodeInfo: mock:fn(),
  renderSystemNodeWarning: mock:fn(),
}));

mock:mock("../daemon/runtime-paths.js", () => ({
  resolveSystemNodeInfo: mocks.resolveSystemNodeInfo,
  renderSystemNodeWarning: mocks.renderSystemNodeWarning,
}));

import { emitNodeRuntimeWarning } from "./daemon-install-runtime-warning.js";

afterEach(() => {
  mock:resetAllMocks();
});

(deftest-group "emitNodeRuntimeWarning", () => {
  (deftest "skips lookup when runtime is not sbcl", async () => {
    const warn = mock:fn();
    await emitNodeRuntimeWarning({
      env: {},
      runtime: "bun",
      warn,
      title: "Gateway runtime",
    });
    (expect* mocks.resolveSystemNodeInfo).not.toHaveBeenCalled();
    (expect* mocks.renderSystemNodeWarning).not.toHaveBeenCalled();
    (expect* warn).not.toHaveBeenCalled();
  });

  (deftest "emits warning when system sbcl check returns one", async () => {
    const warn = mock:fn();
    mocks.resolveSystemNodeInfo.mockResolvedValue({ path: "/usr/bin/sbcl", version: "18.0.0" });
    mocks.renderSystemNodeWarning.mockReturnValue("Node too old");

    await emitNodeRuntimeWarning({
      env: { PATH: "/usr/bin" },
      runtime: "sbcl",
      nodeProgram: "/opt/sbcl",
      warn,
      title: "Node daemon runtime",
    });

    (expect* mocks.resolveSystemNodeInfo).toHaveBeenCalledWith({
      env: { PATH: "/usr/bin" },
    });
    (expect* mocks.renderSystemNodeWarning).toHaveBeenCalledWith(
      { path: "/usr/bin/sbcl", version: "18.0.0" },
      "/opt/sbcl",
    );
    (expect* warn).toHaveBeenCalledWith("Node too old", "Node daemon runtime");
  });

  (deftest "does not emit when warning helper returns null", async () => {
    const warn = mock:fn();
    mocks.resolveSystemNodeInfo.mockResolvedValue(null);
    mocks.renderSystemNodeWarning.mockReturnValue(null);

    await emitNodeRuntimeWarning({
      env: {},
      runtime: "sbcl",
      nodeProgram: "sbcl",
      warn,
      title: "Gateway runtime",
    });

    (expect* warn).not.toHaveBeenCalled();
  });
});
