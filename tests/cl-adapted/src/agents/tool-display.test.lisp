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
import { formatToolDetail, resolveToolDisplay } from "./tool-display.js";

(deftest-group "tool display details", () => {
  (deftest "skips zero/false values for optional detail fields", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "sessions_spawn",
        args: {
          task: "double-message-bug-gpt",
          label: 0,
          runTimeoutSeconds: 0,
        },
      }),
    );

    (expect* detail).is("double-message-bug-gpt");
  });

  (deftest "includes only truthy boolean details", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "message",
        args: {
          action: "react",
          provider: "discord",
          to: "chan-1",
          remove: false,
        },
      }),
    );

    (expect* detail).contains("provider discord");
    (expect* detail).contains("to chan-1");
    (expect* detail).not.contains("remove");
  });

  (deftest "keeps positive numbers and true booleans", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "sessions_history",
        args: {
          sessionKey: "agent:main:main",
          limit: 20,
          includeTools: true,
        },
      }),
    );

    (expect* detail).contains("session agent:main:main");
    (expect* detail).contains("limit 20");
    (expect* detail).contains("tools true");
  });

  (deftest "formats read/write/edit with intent-first file detail", () => {
    const readDetail = formatToolDetail(
      resolveToolDisplay({
        name: "read",
        args: { file_path: "/tmp/a.txt", offset: 2, limit: 2 },
      }),
    );
    const writeDetail = formatToolDetail(
      resolveToolDisplay({
        name: "write",
        args: { file_path: "/tmp/a.txt", content: "abc" },
      }),
    );
    const editDetail = formatToolDetail(
      resolveToolDisplay({
        name: "edit",
        args: { path: "/tmp/a.txt", newText: "abcd" },
      }),
    );

    (expect* readDetail).is("lines 2-3 from /tmp/a.txt");
    (expect* writeDetail).is("to /tmp/a.txt (3 chars)");
    (expect* editDetail).is("in /tmp/a.txt (4 chars)");
  });

  (deftest "formats web_search query with quotes", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "web_search",
        args: { query: "OpenClaw docs", count: 3 },
      }),
    );

    (expect* detail).is('for "OpenClaw docs" (top 3)');
  });

  (deftest "summarizes exec commands with context", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: {
          command:
            "set -euo pipefail\ngit -C /Users/adityasingh/.openclaw/workspace status --short | head -n 3",
          workdir: "/Users/adityasingh/.openclaw/workspace",
        },
      }),
    );

    (expect* detail).contains("check git status -> show first 3 lines");
    (expect* detail).contains(".openclaw/workspace)");
  });

  (deftest "moves cd path to context suffix and appends raw command", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: { command: "cd ~/my-project && npm install" },
      }),
    );

    (expect* detail).is(
      "install dependencies (in ~/my-project)\n\n`cd ~/my-project && npm install`",
    );
  });

  (deftest "moves cd path to context suffix with multiple stages and raw command", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: { command: "cd ~/my-project && npm install && npm test" },
      }),
    );

    (expect* detail).is(
      "install dependencies → run tests (in ~/my-project)\n\n`cd ~/my-project && npm install && npm test`",
    );
  });

  (deftest "moves pushd path to context suffix and appends raw command", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: { command: "pushd /tmp && git status" },
      }),
    );

    (expect* detail).is("check git status (in /tmp)\n\n`pushd /tmp && git status`");
  });

  (deftest "clears inferred cwd when popd is stripped from preamble", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: { command: "pushd /tmp && popd && npm install" },
      }),
    );

    (expect* detail).is("install dependencies\n\n`pushd /tmp && popd && npm install`");
  });

  (deftest "moves cd path to context suffix with || separator", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: { command: "cd /app || npm install" },
      }),
    );

    // || means npm install runs when cd FAILS — cd should NOT be stripped as preamble.
    // Both stages are summarized; cd is not treated as context prefix.
    (expect* detail).toMatch(/^run cd \/app → install dependencies/);
  });

  (deftest "explicit workdir takes priority over cd path", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: { command: "cd /tmp && npm install", workdir: "/app" },
      }),
    );

    (expect* detail).is("install dependencies (in /app)\n\n`cd /tmp && npm install`");
  });

  (deftest "summarizes all stages and appends raw command", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: { command: "git fetch && git rebase origin/main" },
      }),
    );

    (expect* detail).is(
      "fetch git changes → rebase git branch\n\n`git fetch && git rebase origin/main`",
    );
  });

  (deftest "falls back to raw command for unknown binaries", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: { command: "jj rebase -s abc -d main" },
      }),
    );

    (expect* detail).is("jj rebase -s abc -d main");
  });

  (deftest "falls back to raw command for unknown binary with cwd", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: { command: "mycli deploy --prod", workdir: "/app" },
      }),
    );

    (expect* detail).is("mycli deploy --prod (in /app)");
  });

  (deftest "keeps multi-stage summary when only some stages are generic", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: { command: "cargo build && npm test" },
      }),
    );

    // "run cargo build" is generic, but "run tests" is known — keep joined summary
    (expect* detail).toMatch(/^run cargo build → run tests/);
  });

  (deftest "handles standalone cd as raw command", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: { command: "cd /tmp" },
      }),
    );

    // standalone cd (no following command) — treated as raw since it's generic
    (expect* detail).is("cd /tmp");
  });

  (deftest "handles chained cd commands using last path", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: { command: "cd /tmp && cd /app" },
      }),
    );

    // both cd's are preamble; last path wins
    (expect* detail).is("cd /tmp && cd /app (in /app)");
  });

  (deftest "respects quotes when splitting preamble separators", () => {
    const detail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: { command: 'export MSG="foo && bar" && echo test' },
      }),
    );

    // The && inside quotes must not be treated as a separator —
    // summary line should be "print text", not "run export" (which would happen
    // if the quoted && was mistaken for a real separator).
    (expect* detail).toMatch(/^print text/);
  });

  (deftest "recognizes heredoc/inline script exec details", () => {
    const pyDetail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: {
          command: "python3 <<PY\nprint('x')\nPY",
          workdir: "/Users/adityasingh/.openclaw/workspace",
        },
      }),
    );
    const nodeCheckDetail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: {
          command: "sbcl --check /tmp/test.js",
          workdir: "/Users/adityasingh/.openclaw/workspace",
        },
      }),
    );
    const nodeShortCheckDetail = formatToolDetail(
      resolveToolDisplay({
        name: "exec",
        args: {
          command: "sbcl -c /tmp/test.js",
          workdir: "/Users/adityasingh/.openclaw/workspace",
        },
      }),
    );

    (expect* pyDetail).contains("run python3 inline script (heredoc)");
    (expect* nodeCheckDetail).contains("check js syntax for /tmp/test.js");
    (expect* nodeShortCheckDetail).contains("check js syntax for /tmp/test.js");
  });
});
