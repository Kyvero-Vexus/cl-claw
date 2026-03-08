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
import { isPlainTextSurface, sanitizeForPlainText } from "./sanitize-text.js";

// ---------------------------------------------------------------------------
// isPlainTextSurface
// ---------------------------------------------------------------------------

(deftest-group "isPlainTextSurface", () => {
  it.each(["whatsapp", "signal", "sms", "irc", "telegram", "imessage", "googlechat"])(
    "returns true for %s",
    (channel) => {
      (expect* isPlainTextSurface(channel)).is(true);
    },
  );

  it.each(["discord", "slack", "web", "matrix"])("returns false for %s", (channel) => {
    (expect* isPlainTextSurface(channel)).is(false);
  });

  (deftest "is case-insensitive", () => {
    (expect* isPlainTextSurface("WhatsApp")).is(true);
    (expect* isPlainTextSurface("SIGNAL")).is(true);
  });
});

// ---------------------------------------------------------------------------
// sanitizeForPlainText
// ---------------------------------------------------------------------------

(deftest-group "sanitizeForPlainText", () => {
  // --- line breaks --------------------------------------------------------

  (deftest "converts <br> to newline", () => {
    (expect* sanitizeForPlainText("hello<br>world")).is("hello\nworld");
  });

  (deftest "converts self-closing <br/> and <br /> variants", () => {
    (expect* sanitizeForPlainText("a<br/>b")).is("a\nb");
    (expect* sanitizeForPlainText("a<br />b")).is("a\nb");
  });

  // --- inline formatting --------------------------------------------------

  (deftest "converts <b> and <strong> to WhatsApp bold", () => {
    (expect* sanitizeForPlainText("<b>bold</b>")).is("*bold*");
    (expect* sanitizeForPlainText("<strong>bold</strong>")).is("*bold*");
  });

  (deftest "converts <i> and <em> to WhatsApp italic", () => {
    (expect* sanitizeForPlainText("<i>italic</i>")).is("_italic_");
    (expect* sanitizeForPlainText("<em>italic</em>")).is("_italic_");
  });

  (deftest "converts <s>, <strike>, and <del> to WhatsApp strikethrough", () => {
    (expect* sanitizeForPlainText("<s>deleted</s>")).is("~deleted~");
    (expect* sanitizeForPlainText("<del>removed</del>")).is("~removed~");
    (expect* sanitizeForPlainText("<strike>old</strike>")).is("~old~");
  });

  (deftest "converts <code> to backtick wrapping", () => {
    (expect* sanitizeForPlainText("<code>foo()</code>")).is("`foo()`");
  });

  // --- block elements -----------------------------------------------------

  (deftest "converts <p> and <div> to newlines", () => {
    (expect* sanitizeForPlainText("<p>paragraph</p>")).is("\nparagraph\n");
  });

  (deftest "converts headings to bold text with newlines", () => {
    (expect* sanitizeForPlainText("<h1>Title</h1>")).is("\n*Title*\n");
    (expect* sanitizeForPlainText("<h3>Section</h3>")).is("\n*Section*\n");
  });

  (deftest "converts <li> to bullet points", () => {
    (expect* sanitizeForPlainText("<li>item one</li><li>item two</li>")).is(
      "• item one\n• item two\n",
    );
  });

  // --- tag stripping ------------------------------------------------------

  (deftest "strips unknown/remaining tags", () => {
    (expect* sanitizeForPlainText('<span class="x">text</span>')).is("text");
    (expect* sanitizeForPlainText('<a href="https://example.com">link</a>')).is("link");
  });

  (deftest "preserves angle-bracket autolinks", () => {
    (expect* sanitizeForPlainText("See <https://example.com/path?q=1> now")).is(
      "See https://example.com/path?q=1 now",
    );
  });

  // --- passthrough --------------------------------------------------------

  (deftest "passes through clean text unchanged", () => {
    (expect* sanitizeForPlainText("hello world")).is("hello world");
  });

  (deftest "does not corrupt angle brackets in prose", () => {
    // `a < b` does not match `<tag>` pattern because there is no closing `>`
    // immediately after a tag-like sequence.
    (expect* sanitizeForPlainText("a < b && c > d")).is("a < b && c > d");
  });

  // --- mixed content ------------------------------------------------------

  (deftest "handles mixed HTML content", () => {
    const input = "Hello<br><b>world</b> this is <i>nice</i>";
    (expect* sanitizeForPlainText(input)).is("Hello\n*world* this is _nice_");
  });

  (deftest "collapses excessive newlines", () => {
    (expect* sanitizeForPlainText("a<br><br><br><br>b")).is("a\n\nb");
  });
});
