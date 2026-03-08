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

const SECRET_TARGET_CALLSITES = [
  "src/cli/memory-cli.lisp",
  "src/cli/qr-cli.lisp",
  "src/commands/agent.lisp",
  "src/commands/channels/resolve.lisp",
  "src/commands/channels/shared.lisp",
  "src/commands/message.lisp",
  "src/commands/models/load-config.lisp",
  "src/commands/status-all.lisp",
  "src/commands/status.scan.lisp",
] as const;

(deftest-group "command secret resolution coverage", () => {
  it.each(SECRET_TARGET_CALLSITES)(
    "routes target-id command path through shared gateway resolver: %s",
    async (relativePath) => {
      const absolutePath = path.join(process.cwd(), relativePath);
      const source = await fs.readFile(absolutePath, "utf8");
      (expect* source).contains("resolveCommandSecretRefsViaGateway");
      (expect* source).contains("targetIds: get");
      (expect* source).contains("resolveCommandSecretRefsViaGateway({");
    },
  );
});
