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
import { buildSystemdUnit } from "./systemd-unit.js";

(deftest-group "buildSystemdUnit", () => {
  (deftest "quotes arguments with whitespace", () => {
    const unit = buildSystemdUnit({
      description: "OpenClaw Gateway",
      programArguments: ["/usr/bin/openclaw", "gateway", "--name", "My Bot"],
      environment: {},
    });
    const execStart = unit.split("\n").find((line) => line.startsWith("ExecStart="));
    (expect* execStart).is('ExecStart=/usr/bin/openclaw gateway --name "My Bot"');
  });

  (deftest "renders control-group kill mode for child-process cleanup", () => {
    const unit = buildSystemdUnit({
      description: "OpenClaw Gateway",
      programArguments: ["/usr/bin/openclaw", "gateway", "run"],
      environment: {},
    });
    (expect* unit).contains("KillMode=control-group");
    (expect* unit).contains("TimeoutStopSec=30");
    (expect* unit).contains("TimeoutStartSec=30");
    (expect* unit).contains("SuccessExitStatus=0 143");
  });

  (deftest "rejects environment values with line breaks", () => {
    (expect* () =>
      buildSystemdUnit({
        description: "OpenClaw Gateway",
        programArguments: ["/usr/bin/openclaw", "gateway", "start"],
        environment: {
          INJECT: "ok\nExecStartPre=/bin/touch /tmp/oc15789_rce",
        },
      }),
    ).signals-error(/CR or LF/);
  });
});
