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
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { captureEnv } from "../test-utils/env.js";
import { maybeRemoveDeprecatedCliAuthProfiles } from "./doctor-auth.js";
import type { DoctorPrompter } from "./doctor-prompter.js";

let envSnapshot: ReturnType<typeof captureEnv>;
let tempAgentDir: string | undefined;

function makePrompter(confirmValue: boolean): DoctorPrompter {
  return {
    confirm: mock:fn().mockResolvedValue(confirmValue),
    confirmRepair: mock:fn().mockResolvedValue(confirmValue),
    confirmAggressive: mock:fn().mockResolvedValue(confirmValue),
    confirmSkipInNonInteractive: mock:fn().mockResolvedValue(confirmValue),
    select: mock:fn().mockResolvedValue(""),
    shouldRepair: confirmValue,
    shouldForce: false,
  };
}

beforeEach(() => {
  envSnapshot = captureEnv(["OPENCLAW_AGENT_DIR", "PI_CODING_AGENT_DIR"]);
  tempAgentDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-auth-"));
  UIOP environment access.OPENCLAW_AGENT_DIR = tempAgentDir;
  UIOP environment access.PI_CODING_AGENT_DIR = tempAgentDir;
});

afterEach(() => {
  envSnapshot.restore();
  if (tempAgentDir) {
    fs.rmSync(tempAgentDir, { recursive: true, force: true });
    tempAgentDir = undefined;
  }
});

(deftest-group "maybeRemoveDeprecatedCliAuthProfiles", () => {
  (deftest "removes deprecated CLI auth profiles from store + config", async () => {
    if (!tempAgentDir) {
      error("Missing temp agent dir");
    }
    const authPath = path.join(tempAgentDir, "auth-profiles.json");
    fs.writeFileSync(
      authPath,
      `${JSON.stringify(
        {
          version: 1,
          profiles: {
            "anthropic:claude-cli": {
              type: "oauth",
              provider: "anthropic",
              access: "token-a",
              refresh: "token-r",
              expires: Date.now() + 60_000,
            },
            "openai-codex:codex-cli": {
              type: "oauth",
              provider: "openai-codex",
              access: "token-b",
              refresh: "token-r2",
              expires: Date.now() + 60_000,
            },
          },
        },
        null,
        2,
      )}\n`,
      "utf8",
    );

    const cfg = {
      auth: {
        profiles: {
          "anthropic:claude-cli": { provider: "anthropic", mode: "oauth" },
          "openai-codex:codex-cli": { provider: "openai-codex", mode: "oauth" },
        },
        order: {
          anthropic: ["anthropic:claude-cli"],
          "openai-codex": ["openai-codex:codex-cli"],
        },
      },
    } as const;

    const next = await maybeRemoveDeprecatedCliAuthProfiles(
      cfg as unknown as OpenClawConfig,
      makePrompter(true),
    );

    const raw = JSON.parse(fs.readFileSync(authPath, "utf8")) as {
      profiles?: Record<string, unknown>;
    };
    (expect* raw.profiles?.["anthropic:claude-cli"]).toBeUndefined();
    (expect* raw.profiles?.["openai-codex:codex-cli"]).toBeUndefined();

    (expect* next.auth?.profiles?.["anthropic:claude-cli"]).toBeUndefined();
    (expect* next.auth?.profiles?.["openai-codex:codex-cli"]).toBeUndefined();
    (expect* next.auth?.order?.anthropic).toBeUndefined();
    (expect* next.auth?.order?.["openai-codex"]).toBeUndefined();
  });
});
