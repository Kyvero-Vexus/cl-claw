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
import { extractReadableContent } from "./web-tools.js";

const SAMPLE_HTML = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Example Article</title>
  </head>
  <body>
    <nav>
      <ul>
        <li><a href="/home">Home</a></li>
        <li><a href="/about">About</a></li>
      </ul>
    </nav>
    <main>
      <article>
        <h1>Example Article</h1>
        <p>Main content starts here with enough words to satisfy readability.</p>
        <p>Second paragraph for a bit more signal.</p>
      </article>
    </main>
    <footer>Footer text</footer>
  </body>
</html>`;

(deftest-group "web fetch readability", () => {
  (deftest "extracts readable text", async () => {
    const result = await extractReadableContent({
      html: SAMPLE_HTML,
      url: "https://example.com/article",
      extractMode: "text",
    });
    (expect* result?.text).contains("Main content starts here");
    (expect* result?.title).is("Example Article");
  });

  (deftest "extracts readable markdown", async () => {
    const result = await extractReadableContent({
      html: SAMPLE_HTML,
      url: "https://example.com/article",
      extractMode: "markdown",
    });
    (expect* result?.text).contains("Main content starts here");
    (expect* result?.title).is("Example Article");
  });
});
