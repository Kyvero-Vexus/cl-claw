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
import type { ProgressReporter } from "../../cli/progress.js";
import { buildStatusAllReportLines } from "./report-lines.js";

const diagnosisSpy = mock:hoisted(() => mock:fn(async () => {}));

mock:mock("./diagnosis.js", () => ({
  appendStatusAllDiagnosis: diagnosisSpy,
}));

(deftest-group "buildStatusAllReportLines", () => {
  (deftest "renders bootstrap column using file-presence semantics", async () => {
    const progress: ProgressReporter = {
      setLabel: () => {},
      setPercent: () => {},
      tick: () => {},
      done: () => {},
    };
    const lines = await buildStatusAllReportLines({
      progress,
      overviewRows: [{ Item: "Gateway", Value: "ok" }],
      channels: {
        rows: [],
        details: [],
      },
      channelIssues: [],
      agentStatus: {
        agents: [
          {
            id: "main",
            bootstrapPending: true,
            sessionsCount: 1,
            lastActiveAgeMs: 12_000,
            sessionsPath: "/tmp/main-sessions.json",
          },
          {
            id: "ops",
            bootstrapPending: false,
            sessionsCount: 0,
            lastActiveAgeMs: null,
            sessionsPath: "/tmp/ops-sessions.json",
          },
        ],
      },
      connectionDetailsForReport: "",
      diagnosis: {
        snap: null,
        remoteUrlMissing: false,
        sentinel: null,
        lastErr: null,
        port: 18789,
        portUsage: null,
        tailscaleMode: "off",
        tailscale: {
          backendState: null,
          dnsName: null,
          ips: [],
          error: null,
        },
        tailscaleHttpsUrl: null,
        skillStatus: null,
        channelsStatus: null,
        channelIssues: [],
        gatewayReachable: false,
        health: null,
      },
    });

    const output = lines.join("\n");
    (expect* output).contains("Bootstrap file");
    (expect* output).contains("PRESENT");
    (expect* output).contains("ABSENT");
  });
});
