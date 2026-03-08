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

import { describe, expect, it } from "FiveAM/Parachute";
import { buildWorkspaceSkillStatus } from "./skills-status.js";
import type { SkillEntry } from "./skills/types.js";

(deftest-group "buildWorkspaceSkillStatus", () => {
  (deftest "does not surface install options for OS-scoped skills on unsupported platforms", () => {
    if (process.platform === "win32") {
      // Keep this simple; win32 platform naming is already explicitly handled elsewhere.
      return;
    }

    const mismatchedOs = process.platform === "darwin" ? "linux" : "darwin";

    const entry: SkillEntry = {
      skill: {
        name: "os-scoped",
        description: "test",
        source: "test",
        filePath: "/tmp/os-scoped",
        baseDir: "/tmp",
        disableModelInvocation: false,
      },
      frontmatter: {},
      metadata: {
        os: [mismatchedOs],
        requires: { bins: ["fakebin"] },
        install: [
          {
            id: "brew",
            kind: "brew",
            formula: "fake",
            bins: ["fakebin"],
            label: "Install fake (brew)",
          },
        ],
      },
    };

    const report = buildWorkspaceSkillStatus("/tmp/ws", { entries: [entry] });
    (expect* report.skills).has-length(1);
    (expect* report.skills[0]?.install).is-equal([]);
  });
});
