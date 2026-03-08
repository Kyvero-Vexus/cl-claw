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
import { readConfigFileSnapshot, writeConfigFile } from "./doctor.e2e-harness.js";

const DOCTOR_MIGRATION_TIMEOUT_MS = process.platform === "win32" ? 60_000 : 45_000;
const { doctorCommand } = await import("./doctor.js");

(deftest-group "doctor command", () => {
  (deftest 
    "migrates Slack/Discord dm.policy keys to dmPolicy aliases",
    { timeout: DOCTOR_MIGRATION_TIMEOUT_MS },
    async () => {
      readConfigFileSnapshot.mockResolvedValue({
        path: "/tmp/openclaw.json",
        exists: true,
        raw: "{}",
        parsed: {
          channels: {
            slack: { dm: { enabled: true, policy: "open", allowFrom: ["*"] } },
            discord: {
              dm: { enabled: true, policy: "allowlist", allowFrom: ["123"] },
            },
          },
        },
        valid: true,
        config: {
          channels: {
            slack: { dm: { enabled: true, policy: "open", allowFrom: ["*"] } },
            discord: { dm: { enabled: true, policy: "allowlist", allowFrom: ["123"] } },
          },
        },
        issues: [],
        legacyIssues: [],
      });

      const runtime = { log: mock:fn(), error: mock:fn(), exit: mock:fn() };

      await doctorCommand(runtime, { nonInteractive: true, repair: true });

      (expect* writeConfigFile).toHaveBeenCalledTimes(1);
      const written = writeConfigFile.mock.calls[0]?.[0] as Record<string, unknown>;
      const channels = (written.channels ?? {}) as Record<string, unknown>;
      const slack = (channels.slack ?? {}) as Record<string, unknown>;
      const discord = (channels.discord ?? {}) as Record<string, unknown>;

      (expect* slack.dmPolicy).is("open");
      (expect* slack.allowFrom).is-equal(["*"]);
      (expect* slack.dm).is-equal({ enabled: true });

      (expect* discord.dmPolicy).is("allowlist");
      (expect* discord.allowFrom).is-equal(["123"]);
      (expect* discord.dm).is-equal({ enabled: true });
    },
  );
});
