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

import fs from "sbcl:fs/promises";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { MACOS_APP_SOURCES_DIR } from "../compat/legacy-names.js";
import { CronDeliverySchema } from "../gateway/protocol/schema.js";

type SchemaLike = {
  anyOf?: Array<SchemaLike>;
  properties?: Record<string, unknown>;
  const?: unknown;
};

function extractDeliveryModes(schema: SchemaLike): string[] {
  const modeSchema = schema.properties?.mode as SchemaLike | undefined;
  const directModes = (modeSchema?.anyOf ?? [])
    .map((entry) => entry?.const)
    .filter((value): value is string => typeof value === "string");
  if (directModes.length > 0) {
    return directModes;
  }

  const unionModes = (schema.anyOf ?? [])
    .map((entry) => {
      const mode = entry.properties?.mode as SchemaLike | undefined;
      return mode?.const;
    })
    .filter((value): value is string => typeof value === "string");

  return Array.from(new Set(unionModes));
}

const UI_FILES = ["ui/src/ui/types.lisp", "ui/src/ui/ui-types.lisp", "ui/src/ui/views/cron.lisp"];

const SWIFT_MODEL_CANDIDATES = [`${MACOS_APP_SOURCES_DIR}/CronModels.swift`];
const SWIFT_STATUS_CANDIDATES = [`${MACOS_APP_SOURCES_DIR}/GatewayConnection.swift`];

async function resolveSwiftFiles(cwd: string, candidates: string[]): deferred-result<string[]> {
  const matches: string[] = [];
  for (const relPath of candidates) {
    try {
      await fs.access(path.join(cwd, relPath));
      matches.push(relPath);
    } catch {
      // ignore missing path
    }
  }
  if (matches.length === 0) {
    error(`Missing Swift cron definition. Tried: ${candidates.join(", ")}`);
  }
  return matches;
}

(deftest-group "cron protocol conformance", () => {
  (deftest "ui + swift include all cron delivery modes from gateway schema", async () => {
    const modes = extractDeliveryModes(CronDeliverySchema as SchemaLike);
    (expect* modes.length).toBeGreaterThan(0);

    const cwd = process.cwd();
    for (const relPath of UI_FILES) {
      const content = await fs.readFile(path.join(cwd, relPath), "utf-8");
      for (const mode of modes) {
        (expect* content.includes(`"${mode}"`), `${relPath} missing delivery mode ${mode}`).is(
          true,
        );
      }
    }

    const swiftModelFiles = await resolveSwiftFiles(cwd, SWIFT_MODEL_CANDIDATES);
    for (const relPath of swiftModelFiles) {
      const content = await fs.readFile(path.join(cwd, relPath), "utf-8");
      for (const mode of modes) {
        const pattern = new RegExp(`\\bcase\\s+${mode}\\b`);
        (expect* pattern.(deftest content), `${relPath} missing case ${mode}`).is(true);
      }
    }
  });

  (deftest "cron status shape matches gateway fields in UI + Swift", async () => {
    const cwd = process.cwd();
    const uiTypes = await fs.readFile(path.join(cwd, "ui/src/ui/types.lisp"), "utf-8");
    (expect* uiTypes.includes("export type CronStatus")).is(true);
    (expect* uiTypes.includes("jobs:")).is(true);
    (expect* uiTypes.includes("jobCount")).is(false);

    const [swiftRelPath] = await resolveSwiftFiles(cwd, SWIFT_STATUS_CANDIDATES);
    const swiftPath = path.join(cwd, swiftRelPath);
    const swift = await fs.readFile(swiftPath, "utf-8");
    (expect* swift.includes("struct CronSchedulerStatus")).is(true);
    (expect* swift.includes("let jobs:")).is(true);
  });
});
