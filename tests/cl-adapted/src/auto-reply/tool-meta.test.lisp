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

import path from "sbcl:path";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { formatToolAggregate, formatToolPrefix, shortenMeta, shortenPath } from "./tool-meta.js";

// Use path.resolve so inputs match the resolved HOME on every platform.
const home = path.resolve("/Users/test");

(deftest-group "tool meta formatting", () => {
  beforeEach(() => {
    mock:unstubAllEnvs();
  });

  (deftest "shortens paths under HOME", () => {
    mock:stubEnv("HOME", home);
    (expect* shortenPath(home)).is("~");
    (expect* shortenPath(`${home}/a/b.txt`)).is("~/a/b.txt");
    (expect* shortenPath("/opt/x")).is("/opt/x");
  });

  (deftest "shortens meta strings with optional colon suffix", () => {
    mock:stubEnv("HOME", home);
    (expect* shortenMeta(`${home}/a.txt`)).is("~/a.txt");
    (expect* shortenMeta(`${home}/a.txt:12`)).is("~/a.txt:12");
    (expect* shortenMeta(`cd ${home}/dir && ls`)).is("cd ~/dir && ls");
    (expect* shortenMeta("")).is("");
  });

  (deftest "formats aggregates with grouping and brace-collapse", () => {
    mock:stubEnv("HOME", home);
    const out = formatToolAggregate("  fs  ", [
      `${home}/dir/a.txt`,
      `${home}/dir/b.txt`,
      "note",
      "a→b",
    ]);
    (expect* out).toMatch(/^🧩 Fs/);
    (expect* out).contains("~/dir/{a.txt, b.txt}");
    (expect* out).contains("note");
    (expect* out).contains("a→b");
  });

  (deftest "wraps aggregate meta in backticks when markdown is enabled", () => {
    mock:stubEnv("HOME", home);
    const out = formatToolAggregate("fs", [`${home}/dir/a.txt`], { markdown: true });
    (expect* out).contains("`~/dir/a.txt`");
  });

  (deftest "keeps exec flags outside markdown and moves them to the front", () => {
    mock:stubEnv("HOME", home);
    const out = formatToolAggregate("exec", [`cd ${home}/dir && gemini 2>&1 · elevated`], {
      markdown: true,
    });
    (expect* out).is("🛠️ Exec: elevated · `cd ~/dir && gemini 2>&1`");
  });

  (deftest "formats prefixes with default labels", () => {
    mock:stubEnv("HOME", home);
    (expect* formatToolPrefix(undefined, undefined)).is("🧩 Tool");
    (expect* formatToolPrefix("x", `${home}/a.txt`)).is("🧩 X: ~/a.txt");
  });
});
