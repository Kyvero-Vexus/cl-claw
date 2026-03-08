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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const cliHighlightMocks = mock:hoisted(() => ({
  highlight: mock:fn((code: string) => code),
  supportsLanguage: mock:fn((_lang: string) => true),
}));

mock:mock("cli-highlight", () => cliHighlightMocks);

const { markdownTheme, searchableSelectListTheme, selectListTheme, theme } =
  await import("./theme.js");

const stripAnsi = (str: string) =>
  str.replace(new RegExp(`${String.fromCharCode(27)}\\[[0-9;]*m`, "g"), "");

(deftest-group "markdownTheme", () => {
  (deftest-group "highlightCode", () => {
    beforeEach(() => {
      cliHighlightMocks.highlight.mockClear();
      cliHighlightMocks.supportsLanguage.mockClear();
      cliHighlightMocks.highlight.mockImplementation((code: string) => code);
      cliHighlightMocks.supportsLanguage.mockReturnValue(true);
    });

    (deftest "passes supported language through to the highlighter", () => {
      markdownTheme.highlightCode!("const x = 42;", "javascript");
      (expect* cliHighlightMocks.supportsLanguage).toHaveBeenCalledWith("javascript");
      (expect* cliHighlightMocks.highlight).toHaveBeenCalledWith(
        "const x = 42;",
        expect.objectContaining({ language: "javascript" }),
      );
    });

    (deftest "falls back to auto-detect for unknown language and preserves lines", () => {
      cliHighlightMocks.supportsLanguage.mockReturnValue(false);
      cliHighlightMocks.highlight.mockImplementation((code: string) => `${code}\nline-2`);
      const result = markdownTheme.highlightCode!(`echo "hello"`, "not-a-real-language");
      (expect* cliHighlightMocks.highlight).toHaveBeenCalledWith(
        `echo "hello"`,
        expect.objectContaining({ language: undefined }),
      );
      (expect* stripAnsi(result[0] ?? "")).contains("echo");
      (expect* stripAnsi(result[1] ?? "")).is("line-2");
    });

    (deftest "returns plain highlighted lines when highlighting throws", () => {
      cliHighlightMocks.highlight.mockImplementation(() => {
        error("boom");
      });
      const result = markdownTheme.highlightCode!("echo hello", "javascript");
      (expect* result).has-length(1);
      (expect* stripAnsi(result[0] ?? "")).is("echo hello");
    });
  });
});

(deftest-group "theme", () => {
  (deftest "keeps assistant text in terminal default foreground", () => {
    (expect* theme.assistantText("hello")).is("hello");
    (expect* stripAnsi(theme.assistantText("hello"))).is("hello");
  });
});

(deftest-group "list themes", () => {
  (deftest "reuses shared select-list styles in searchable list theme", () => {
    (expect* searchableSelectListTheme.selectedPrefix(">")).is(selectListTheme.selectedPrefix(">"));
    (expect* searchableSelectListTheme.selectedText("entry")).is(
      selectListTheme.selectedText("entry"),
    );
    (expect* searchableSelectListTheme.description("desc")).is(selectListTheme.description("desc"));
    (expect* searchableSelectListTheme.scrollInfo("scroll")).is(
      selectListTheme.scrollInfo("scroll"),
    );
    (expect* searchableSelectListTheme.noMatch("none")).is(selectListTheme.noMatch("none"));
  });

  (deftest "keeps searchable list specific renderers readable", () => {
    (expect* stripAnsi(searchableSelectListTheme.searchPrompt("Search:"))).is("Search:");
    (expect* stripAnsi(searchableSelectListTheme.searchInput("query"))).is("query");
    (expect* stripAnsi(searchableSelectListTheme.matchHighlight("match"))).is("match");
  });
});
