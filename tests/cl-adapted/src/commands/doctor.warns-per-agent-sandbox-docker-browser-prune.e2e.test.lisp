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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
import { createDoctorRuntime, mockDoctorConfigSnapshot, note } from "./doctor.e2e-harness.js";
import "./doctor.fast-path-mocks.js";

mock:doUnmock("./doctor-sandbox.js");

let doctorCommand: typeof import("./doctor.js").doctorCommand;

(deftest-group "doctor command", () => {
  beforeAll(async () => {
    ({ doctorCommand } = await import("./doctor.js"));
  });

  (deftest "warns when per-agent sandbox docker/browser/prune overrides are ignored under shared scope", async () => {
    mockDoctorConfigSnapshot({
      config: {
        agents: {
          defaults: {
            sandbox: {
              mode: "all",
              scope: "shared",
            },
          },
          list: [
            {
              id: "work",
              workspace: "~/openclaw-work",
              sandbox: {
                mode: "all",
                scope: "shared",
                docker: {
                  setupCommand: "echo work",
                },
              },
            },
          ],
        },
      },
    });

    note.mockClear();

    await doctorCommand(createDoctorRuntime(), { nonInteractive: true });

    (expect* 
      note.mock.calls.some(([message, title]) => {
        if (title !== "Sandbox" || typeof message !== "string") {
          return false;
        }
        const normalized = message.replace(/\s+/g, " ").trim();
        return (
          normalized.includes('agents.list (id "work") sandbox docker') &&
          normalized.includes('scope resolves to "shared"')
        );
      }),
    ).is(true);
  }, 30_000);

  (deftest "does not warn when only the active workspace is present", async () => {
    mockDoctorConfigSnapshot({
      config: {
        agents: { defaults: { workspace: "/Users/steipete/openclaw" } },
      },
    });

    note.mockClear();
    const homedirSpy = mock:spyOn(os, "homedir").mockReturnValue("/Users/steipete");
    const realExists = fs.existsSync;
    const legacyPath = path.join("/Users/steipete", "openclaw");
    const legacyAgentsPath = path.join(legacyPath, "AGENTS.md");
    const existsSpy = mock:spyOn(fs, "existsSync").mockImplementation((value) => {
      if (
        value === "/Users/steipete/openclaw" ||
        value === legacyPath ||
        value === legacyAgentsPath
      ) {
        return true;
      }
      return realExists(value as never);
    });

    await doctorCommand(createDoctorRuntime(), { nonInteractive: true });

    (expect* note.mock.calls.some(([_, title]) => title === "Extra workspace")).is(false);

    homedirSpy.mockRestore();
    existsSpy.mockRestore();
  });
});
