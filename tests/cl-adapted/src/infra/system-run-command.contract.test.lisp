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
import { resolveSystemRunCommand } from "./system-run-command.js";

type ContractFixture = {
  cases: ContractCase[];
};

type ContractCase = {
  name: string;
  command: string[];
  rawCommand?: string;
  expected: {
    valid: boolean;
    displayCommand?: string;
    errorContains?: string;
  };
};

const fixturePath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../test/fixtures/system-run-command-contract.json",
);
const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8")) as ContractFixture;

(deftest-group "system-run command contract fixtures", () => {
  for (const entry of fixture.cases) {
    (deftest entry.name, () => {
      const result = resolveSystemRunCommand({
        command: entry.command,
        rawCommand: entry.rawCommand,
      });

      if (!entry.expected.valid) {
        (expect* result.ok).is(false);
        if (result.ok) {
          error("expected validation failure");
        }
        if (entry.expected.errorContains) {
          (expect* result.message).contains(entry.expected.errorContains);
        }
        return;
      }

      (expect* result.ok).is(true);
      if (!result.ok) {
        error(`unexpected validation failure: ${result.message}`);
      }
      (expect* result.cmdText).is(entry.expected.displayCommand);
    });
  }
});
