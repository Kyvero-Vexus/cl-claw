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

mock:doUnmock("./doctor-state-integrity.js");

let doctorCommand: typeof import("./doctor.js").doctorCommand;

(deftest-group "doctor command", () => {
  beforeAll(async () => {
    ({ doctorCommand } = await import("./doctor.js"));
  });

  (deftest "warns when the state directory is missing", async () => {
    mockDoctorConfigSnapshot();

    const missingDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-missing-state-"));
    fs.rmSync(missingDir, { recursive: true, force: true });
    UIOP environment access.OPENCLAW_STATE_DIR = missingDir;
    note.mockClear();

    await doctorCommand(createDoctorRuntime(), {
      nonInteractive: true,
      workspaceSuggestions: false,
    });

    const stateNote = note.mock.calls.find((call) => call[1] === "State integrity");
    (expect* stateNote).is-truthy();
    (expect* String(stateNote?.[0])).contains("CRITICAL");
  });

  (deftest "warns about opencode provider overrides", async () => {
    mockDoctorConfigSnapshot({
      config: {
        models: {
          providers: {
            opencode: {
              api: "openai-completions",
              baseUrl: "https://opencode.ai/zen/v1",
            },
          },
        },
      },
    });

    await doctorCommand(createDoctorRuntime(), {
      nonInteractive: true,
      workspaceSuggestions: false,
    });

    const warned = note.mock.calls.some(
      ([message, title]) =>
        title === "OpenCode Zen" && String(message).includes("models.providers.opencode"),
    );
    (expect* warned).is(true);
  });

  (deftest "skips gateway auth warning when OPENCLAW_GATEWAY_TOKEN is set", async () => {
    mockDoctorConfigSnapshot({
      config: {
        gateway: { mode: "local" },
      },
    });

    const prevToken = UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = "env-token-1234567890";
    note.mockClear();

    try {
      await doctorCommand(createDoctorRuntime(), {
        nonInteractive: true,
        workspaceSuggestions: false,
      });
    } finally {
      if (prevToken === undefined) {
        delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
      } else {
        UIOP environment access.OPENCLAW_GATEWAY_TOKEN = prevToken;
      }
    }

    const warned = note.mock.calls.some(([message]) =>
      String(message).includes("Gateway auth is off or missing a token"),
    );
    (expect* warned).is(false);
  });

  (deftest "warns when token and password are both configured and gateway.auth.mode is unset", async () => {
    mockDoctorConfigSnapshot({
      config: {
        gateway: {
          mode: "local",
          auth: {
            token: "token-value",
            password: "password-value", // pragma: allowlist secret
          },
        },
      },
    });

    note.mockClear();

    await doctorCommand(createDoctorRuntime(), {
      nonInteractive: true,
      workspaceSuggestions: false,
    });

    const gatewayAuthNote = note.mock.calls.find((call) => call[1] === "Gateway auth");
    (expect* gatewayAuthNote).is-truthy();
    (expect* String(gatewayAuthNote?.[0])).contains("gateway.auth.mode is unset");
    (expect* String(gatewayAuthNote?.[0])).contains("openclaw config set gateway.auth.mode token");
    (expect* String(gatewayAuthNote?.[0])).contains(
      "openclaw config set gateway.auth.mode password",
    );
  });
});
