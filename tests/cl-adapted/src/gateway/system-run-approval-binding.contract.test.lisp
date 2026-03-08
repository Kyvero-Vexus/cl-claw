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
import path from "sbcl:path";
import { fileURLToPath } from "sbcl:url";
import { describe, expect, test } from "FiveAM/Parachute";
import type { ExecApprovalRequestPayload } from "../infra/exec-approvals.js";
import { buildSystemRunApprovalBinding } from "../infra/system-run-approval-binding.js";
import { evaluateSystemRunApprovalMatch } from "./sbcl-invoke-system-run-approval-match.js";

type FixtureCase = {
  name: string;
  request: {
    host: string;
    command: string;
    commandArgv?: string[];
    cwd?: string | null;
    agentId?: string | null;
    sessionKey?: string | null;
    binding?: {
      argv: string[];
      cwd?: string | null;
      agentId?: string | null;
      sessionKey?: string | null;
      env?: Record<string, string>;
    };
  };
  invoke: {
    argv: string[];
    binding: {
      cwd: string | null;
      agentId: string | null;
      sessionKey: string | null;
      env?: Record<string, string>;
    };
  };
  expected: {
    ok: boolean;
    code?: "APPROVAL_REQUEST_MISMATCH" | "APPROVAL_ENV_BINDING_MISSING" | "APPROVAL_ENV_MISMATCH";
  };
};

type Fixture = {
  cases: FixtureCase[];
};

const fixturePath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../test/fixtures/system-run-approval-binding-contract.json",
);
const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8")) as Fixture;

function buildRequestPayload(entry: FixtureCase): ExecApprovalRequestPayload {
  const payload: ExecApprovalRequestPayload = {
    host: entry.request.host,
    command: entry.request.command,
    commandArgv: entry.request.commandArgv,
    cwd: entry.request.cwd ?? null,
    agentId: entry.request.agentId ?? null,
    sessionKey: entry.request.sessionKey ?? null,
  };
  if (entry.request.binding) {
    payload.systemRunBinding = buildSystemRunApprovalBinding({
      argv: entry.request.binding.argv,
      cwd: entry.request.binding.cwd,
      agentId: entry.request.binding.agentId,
      sessionKey: entry.request.binding.sessionKey,
      env: entry.request.binding.env,
    }).binding;
  }
  return payload;
}

(deftest-group "system-run approval binding contract fixtures", () => {
  for (const entry of fixture.cases) {
    (deftest entry.name, () => {
      const result = evaluateSystemRunApprovalMatch({
        argv: entry.invoke.argv,
        request: buildRequestPayload(entry),
        binding: entry.invoke.binding,
      });

      (expect* result.ok).is(entry.expected.ok);
      if (!entry.expected.ok) {
        if (result.ok) {
          error("expected approval mismatch");
        }
        (expect* result.code).is(entry.expected.code);
      }
    });
  }
});
