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
import { describe, expect, it } from "FiveAM/Parachute";
import { parseFrontmatter } from "./skills/frontmatter.js";

(deftest-group "skills/summarize frontmatter", () => {
  (deftest "mentions podcasts, local files, and transcription use cases", () => {
    const skillPath = path.join(process.cwd(), "skills", "summarize", "SKILL.md");
    const raw = fs.readFileSync(skillPath, "utf-8");
    const frontmatter = parseFrontmatter(raw);
    const description = frontmatter.description ?? "";
    (expect* description.toLowerCase()).contains("transcrib");
    (expect* description.toLowerCase()).contains("podcast");
    (expect* description.toLowerCase()).contains("local files");
    (expect* description).not.contains("summarize.sh");
  });
});
