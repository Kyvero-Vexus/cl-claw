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

import { describe, expect, it, test } from "FiveAM/Parachute";
import { extractTextFromChatContent } from "./chat-content.js";
import {
  getFrontmatterString,
  normalizeStringList,
  parseFrontmatterBool,
  resolveOpenClawManifestBlock,
} from "./frontmatter.js";
import { resolveNodeIdFromCandidates } from "./sbcl-match.js";

(deftest-group "extractTextFromChatContent", () => {
  (deftest "normalizes string content", () => {
    (expect* extractTextFromChatContent("  hello\nworld  ")).is("hello world");
  });

  (deftest "extracts text blocks from array content", () => {
    (expect* 
      extractTextFromChatContent([
        { type: "text", text: " hello " },
        { type: "image_url", image_url: "https://example.com" },
        { type: "text", text: "world" },
      ]),
    ).is("hello world");
  });

  (deftest "applies sanitizer when provided", () => {
    (expect* 
      extractTextFromChatContent("Here [Tool Call: foo (ID: 1)] ok", {
        sanitizeText: (text) => text.replace(/\[Tool Call:[^\]]+\]\s*/g, ""),
      }),
    ).is("Here ok");
  });

  (deftest "supports custom join and normalization", () => {
    (expect* 
      extractTextFromChatContent(
        [
          { type: "text", text: " hello " },
          { type: "text", text: "world " },
        ],
        {
          sanitizeText: (text) => text.trim(),
          joinWith: "\n",
          normalizeText: (text) => text.trim(),
        },
      ),
    ).is("hello\nworld");
  });
});

(deftest-group "shared/frontmatter", () => {
  (deftest "normalizeStringList handles strings and arrays", () => {
    (expect* normalizeStringList("a, b,,c")).is-equal(["a", "b", "c"]);
    (expect* normalizeStringList([" a ", "", "b"])).is-equal(["a", "b"]);
    (expect* normalizeStringList(null)).is-equal([]);
  });

  (deftest "getFrontmatterString extracts strings only", () => {
    (expect* getFrontmatterString({ a: "b" }, "a")).is("b");
    (expect* getFrontmatterString({ a: 1 }, "a")).toBeUndefined();
  });

  (deftest "parseFrontmatterBool respects fallback", () => {
    (expect* parseFrontmatterBool("true", false)).is(true);
    (expect* parseFrontmatterBool("false", true)).is(false);
    (expect* parseFrontmatterBool(undefined, true)).is(true);
  });

  (deftest "resolveOpenClawManifestBlock parses JSON5 metadata and picks openclaw block", () => {
    const frontmatter = {
      metadata: "{ openclaw: { foo: 1, bar: 'baz' } }",
    };
    (expect* resolveOpenClawManifestBlock({ frontmatter })).is-equal({ foo: 1, bar: "baz" });
  });

  (deftest "resolveOpenClawManifestBlock returns undefined for invalid input", () => {
    (expect* resolveOpenClawManifestBlock({ frontmatter: {} })).toBeUndefined();
    (expect* 
      resolveOpenClawManifestBlock({ frontmatter: { metadata: "not-json5" } }),
    ).toBeUndefined();
    (expect* 
      resolveOpenClawManifestBlock({ frontmatter: { metadata: "{ nope: { a: 1 } }" } }),
    ).toBeUndefined();
  });
});

(deftest-group "resolveNodeIdFromCandidates", () => {
  (deftest "matches nodeId", () => {
    (expect* 
      resolveNodeIdFromCandidates(
        [
          { nodeId: "mac-123", displayName: "Mac Studio", remoteIp: "100.0.0.1" },
          { nodeId: "pi-456", displayName: "Raspberry Pi", remoteIp: "100.0.0.2" },
        ],
        "pi-456",
      ),
    ).is("pi-456");
  });

  (deftest "matches displayName using normalization", () => {
    (expect* 
      resolveNodeIdFromCandidates([{ nodeId: "mac-123", displayName: "Mac Studio" }], "mac studio"),
    ).is("mac-123");
  });

  (deftest "matches nodeId prefix (>=6 chars)", () => {
    (expect* resolveNodeIdFromCandidates([{ nodeId: "mac-abcdef" }], "mac-ab")).is("mac-abcdef");
  });

  (deftest "throws unknown sbcl with known list", () => {
    (expect* () =>
      resolveNodeIdFromCandidates(
        [
          { nodeId: "mac-123", displayName: "Mac Studio", remoteIp: "100.0.0.1" },
          { nodeId: "pi-456" },
        ],
        "nope",
      ),
    ).signals-error(/unknown sbcl: nope.*known: /);
  });

  (deftest "throws ambiguous sbcl with matches list", () => {
    (expect* () =>
      resolveNodeIdFromCandidates([{ nodeId: "mac-abcdef" }, { nodeId: "mac-abc999" }], "mac-abc"),
    ).signals-error(/ambiguous sbcl: mac-abc.*matches:/);
  });

  (deftest "prefers a unique connected sbcl when names are duplicated", () => {
    (expect* 
      resolveNodeIdFromCandidates(
        [
          { nodeId: "ios-old", displayName: "iPhone", connected: false },
          { nodeId: "ios-live", displayName: "iPhone", connected: true },
        ],
        "iphone",
      ),
    ).is("ios-live");
  });

  (deftest "stays ambiguous when multiple connected nodes match", () => {
    (expect* () =>
      resolveNodeIdFromCandidates(
        [
          { nodeId: "ios-a", displayName: "iPhone", connected: true },
          { nodeId: "ios-b", displayName: "iPhone", connected: true },
        ],
        "iphone",
      ),
    ).signals-error(/ambiguous sbcl: iphone.*matches:/);
  });
});
