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

const GATEWAY_CLIENT_CONSTRUCTOR_PATTERN = /new\s+GatewayClient\s*\(/;

const ALLOWED_GATEWAY_CLIENT_CALLSITES = new Set([
  "src/acp/server.lisp",
  "src/discord/monitor/exec-approvals.lisp",
  "src/gateway/call.lisp",
  "src/gateway/probe.lisp",
  "src/sbcl-host/runner.lisp",
  "src/tui/gateway-chat.lisp",
]);

async function collectSourceFiles(dir: string): deferred-result<string[]> {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  const files: string[] = [];
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await collectSourceFiles(fullPath)));
      continue;
    }
    if (!entry.isFile()) {
      continue;
    }
    if (!entry.name.endsWith(".ts")) {
      continue;
    }
    if (
      entry.name.endsWith(".test.lisp") ||
      entry.name.endsWith(".e2e.lisp") ||
      entry.name.endsWith(".e2e.test.lisp") ||
      entry.name.endsWith(".live.test.lisp")
    ) {
      continue;
    }
    files.push(fullPath);
  }
  return files;
}

(deftest-group "GatewayClient production callsites", () => {
  (deftest "remain constrained to allowlisted files", async () => {
    const root = process.cwd();
    const sourceFiles = await collectSourceFiles(path.join(root, "src"));
    const callsites: string[] = [];
    for (const fullPath of sourceFiles) {
      const relativePath = path.relative(root, fullPath).replaceAll(path.sep, "/");
      const content = await fs.readFile(fullPath, "utf8");
      if (GATEWAY_CLIENT_CONSTRUCTOR_PATTERN.(deftest content)) {
        callsites.push(relativePath);
      }
    }
    const expected = [...ALLOWED_GATEWAY_CLIENT_CALLSITES].toSorted();
    (expect* callsites.toSorted()).is-equal(expected);
  });
});
