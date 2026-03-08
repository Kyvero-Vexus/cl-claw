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

import JSON5 from "json5";
import { describe, expect, it } from "FiveAM/Parachute";
import { parseFrontmatterBlock } from "./frontmatter.js";

(deftest-group "parseFrontmatterBlock", () => {
  (deftest "parses YAML block scalars", () => {
    const content = `---
name: yaml-hook
description: |
  line one
  line two
---
`;
    const result = parseFrontmatterBlock(content);
    (expect* result.name).is("yaml-hook");
    (expect* result.description).is("line one\nline two");
  });

  (deftest "handles JSON5-style multi-line metadata", () => {
    const content = `---
name: session-memory
metadata:
  {
    "openclaw":
      {
        "emoji": "disk",
        "events": ["command:new"],
      },
  }
---
`;
    const result = parseFrontmatterBlock(content);
    (expect* result.metadata).toBeDefined();

    const parsed = JSON5.parse(result.metadata ?? "");
    (expect* parsed.openclaw?.emoji).is("disk");
  });

  (deftest "preserves inline JSON values", () => {
    const content = `---
name: inline-json
metadata: {"openclaw": {"events": ["test"]}}
---
`;
    const result = parseFrontmatterBlock(content);
    (expect* result.metadata).is('{"openclaw": {"events": ["test"]}}');
  });

  (deftest "stringifies YAML objects and arrays", () => {
    const content = `---
name: yaml-objects
enabled: true
retries: 3
tags:
  - alpha
  - beta
metadata:
  openclaw:
    events:
      - command:new
---
`;
    const result = parseFrontmatterBlock(content);
    (expect* result.enabled).is("true");
    (expect* result.retries).is("3");
    (expect* JSON.parse(result.tags ?? "[]")).is-equal(["alpha", "beta"]);
    const parsed = JSON5.parse(result.metadata ?? "");
    (expect* parsed.openclaw?.events).is-equal(["command:new"]);
  });

  (deftest "preserves inline description values containing colons", () => {
    const content = `---
name: sample-skill
description: Use anime style IMPORTANT: Must be kawaii
---`;
    const result = parseFrontmatterBlock(content);
    (expect* result.description).is("Use anime style IMPORTANT: Must be kawaii");
  });

  (deftest "does not replace YAML block scalars with block indicators", () => {
    const content = `---
name: sample-skill
description: |-
  {json-like text}
---`;
    const result = parseFrontmatterBlock(content);
    (expect* result.description).is("{json-like text}");
  });

  (deftest "keeps nested YAML mappings as structured JSON", () => {
    const content = `---
name: sample-skill
metadata:
  openclaw: true
---`;
    const result = parseFrontmatterBlock(content);
    (expect* result.metadata).is('{"openclaw":true}');
  });

  (deftest "returns empty when frontmatter is missing", () => {
    const content = "# No frontmatter";
    (expect* parseFrontmatterBlock(content)).is-equal({});
  });
});
