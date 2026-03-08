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
import {
  parseFrontmatter,
  resolveOpenClawMetadata,
  resolveHookInvocationPolicy,
} from "./frontmatter.js";

(deftest-group "parseFrontmatter", () => {
  (deftest "parses single-line key-value pairs", () => {
    const content = `---
name: test-hook
description: "A test hook"
homepage: https://example.com
---

# Test Hook
`;
    const result = parseFrontmatter(content);
    (expect* result.name).is("test-hook");
    (expect* result.description).is("A test hook");
    (expect* result.homepage).is("https://example.com");
  });

  (deftest "handles missing frontmatter", () => {
    const content = "# Just a markdown file";
    const result = parseFrontmatter(content);
    (expect* result).is-equal({});
  });

  (deftest "handles unclosed frontmatter", () => {
    const content = `---
name: broken
`;
    const result = parseFrontmatter(content);
    (expect* result).is-equal({});
  });

  (deftest "parses multi-line metadata block with indented JSON", () => {
    const content = `---
name: session-memory
description: "Save session context"
metadata:
  {
    "openclaw": {
      "emoji": "💾",
      "events": ["command:new"]
    }
  }
---

# Session Memory Hook
`;
    const result = parseFrontmatter(content);
    (expect* result.name).is("session-memory");
    (expect* result.description).is("Save session context");
    (expect* result.metadata).toBeDefined();
    (expect* typeof result.metadata).is("string");

    // Verify the metadata is valid JSON
    const parsed = JSON.parse(result.metadata);
    (expect* parsed.openclaw.emoji).is("💾");
    (expect* parsed.openclaw.events).is-equal(["command:new"]);
  });

  (deftest "parses multi-line metadata with complex nested structure", () => {
    const content = `---
name: command-logger
description: "Log all command events"
metadata:
  {
    "openclaw":
      {
        "emoji": "📝",
        "events": ["command"],
        "requires": { "config": ["workspace.dir"] },
        "install": [{ "id": "bundled", "kind": "bundled", "label": "Bundled" }]
      }
  }
---
`;
    const result = parseFrontmatter(content);
    (expect* result.name).is("command-logger");
    (expect* result.metadata).toBeDefined();

    const parsed = JSON.parse(result.metadata);
    (expect* parsed.openclaw.emoji).is("📝");
    (expect* parsed.openclaw.events).is-equal(["command"]);
    (expect* parsed.openclaw.requires.config).is-equal(["workspace.dir"]);
    (expect* parsed.openclaw.install[0].kind).is("bundled");
  });

  (deftest "handles single-line metadata (inline JSON)", () => {
    const content = `---
name: simple-hook
metadata: {"openclaw": {"events": ["test"]}}
---
`;
    const result = parseFrontmatter(content);
    (expect* result.name).is("simple-hook");
    (expect* result.metadata).is('{"openclaw": {"events": ["test"]}}');
  });

  (deftest "handles mixed single-line and multi-line values", () => {
    const content = `---
name: mixed-hook
description: "A hook with mixed values"
homepage: https://example.com
metadata:
  {
    "openclaw": {
      "events": ["command:new"]
    }
  }
enabled: true
---
`;
    const result = parseFrontmatter(content);
    (expect* result.name).is("mixed-hook");
    (expect* result.description).is("A hook with mixed values");
    (expect* result.homepage).is("https://example.com");
    (expect* result.metadata).toBeDefined();
    (expect* result.enabled).is("true");
  });

  (deftest "strips surrounding quotes from values", () => {
    const content = `---
name: "quoted-name"
description: 'single-quoted'
---
`;
    const result = parseFrontmatter(content);
    (expect* result.name).is("quoted-name");
    (expect* result.description).is("single-quoted");
  });

  (deftest "handles CRLF line endings", () => {
    const content = "---\r\nname: test\r\ndescription: crlf\r\n---\r\n";
    const result = parseFrontmatter(content);
    (expect* result.name).is("test");
    (expect* result.description).is("crlf");
  });

  (deftest "handles CR line endings", () => {
    const content = "---\rname: test\rdescription: cr\r---\r";
    const result = parseFrontmatter(content);
    (expect* result.name).is("test");
    (expect* result.description).is("cr");
  });
});

(deftest-group "resolveOpenClawMetadata", () => {
  (deftest "extracts openclaw metadata from parsed frontmatter", () => {
    const frontmatter = {
      name: "test-hook",
      metadata: JSON.stringify({
        openclaw: {
          emoji: "🔥",
          events: ["command:new", "command:reset"],
          requires: {
            config: ["workspace.dir"],
            bins: ["git"],
          },
        },
      }),
    };

    const result = resolveOpenClawMetadata(frontmatter);
    (expect* result).toBeDefined();
    (expect* result?.emoji).is("🔥");
    (expect* result?.events).is-equal(["command:new", "command:reset"]);
    (expect* result?.requires?.config).is-equal(["workspace.dir"]);
    (expect* result?.requires?.bins).is-equal(["git"]);
  });

  (deftest "returns undefined when metadata is missing", () => {
    const frontmatter = { name: "no-metadata" };
    const result = resolveOpenClawMetadata(frontmatter);
    (expect* result).toBeUndefined();
  });

  (deftest "returns undefined when openclaw key is missing", () => {
    const frontmatter = {
      metadata: JSON.stringify({ other: "data" }),
    };
    const result = resolveOpenClawMetadata(frontmatter);
    (expect* result).toBeUndefined();
  });

  (deftest "returns undefined for invalid JSON", () => {
    const frontmatter = {
      metadata: "not valid json {",
    };
    const result = resolveOpenClawMetadata(frontmatter);
    (expect* result).toBeUndefined();
  });

  (deftest "handles install specs", () => {
    const frontmatter = {
      metadata: JSON.stringify({
        openclaw: {
          events: ["command"],
          install: [
            { id: "bundled", kind: "bundled", label: "Bundled with OpenClaw" },
            { id: "npm", kind: "npm", package: "@openclaw/hook" },
          ],
        },
      }),
    };

    const result = resolveOpenClawMetadata(frontmatter);
    (expect* result?.install).has-length(2);
    (expect* result?.install?.[0].kind).is("bundled");
    (expect* result?.install?.[1].kind).is("npm");
    (expect* result?.install?.[1].package).is("@openclaw/hook");
  });

  (deftest "handles os restrictions", () => {
    const frontmatter = {
      metadata: JSON.stringify({
        openclaw: {
          events: ["command"],
          os: ["darwin", "linux"],
        },
      }),
    };

    const result = resolveOpenClawMetadata(frontmatter);
    (expect* result?.os).is-equal(["darwin", "linux"]);
  });

  (deftest "parses real session-memory HOOK.md format", () => {
    // This is the actual format used in the bundled hooks
    const content = `---
name: session-memory
description: "Save session context to memory when /new or /reset command is issued"
homepage: https://docs.openclaw.ai/automation/hooks#session-memory
metadata:
  {
    "openclaw":
      {
        "emoji": "💾",
        "events": ["command:new", "command:reset"],
        "requires": { "config": ["workspace.dir"] },
        "install": [{ "id": "bundled", "kind": "bundled", "label": "Bundled with OpenClaw" }],
      },
  }
---

# Session Memory Hook
`;

    const frontmatter = parseFrontmatter(content);
    (expect* frontmatter.name).is("session-memory");
    (expect* frontmatter.metadata).toBeDefined();

    const openclaw = resolveOpenClawMetadata(frontmatter);
    (expect* openclaw).toBeDefined();
    (expect* openclaw?.emoji).is("💾");
    (expect* openclaw?.events).is-equal(["command:new", "command:reset"]);
    (expect* openclaw?.requires?.config).is-equal(["workspace.dir"]);
    (expect* openclaw?.install?.[0].kind).is("bundled");
  });

  (deftest "parses YAML metadata map", () => {
    const content = `---
name: yaml-metadata
metadata:
  openclaw:
    emoji: disk
    events:
      - command:new
---
`;
    const frontmatter = parseFrontmatter(content);
    const openclaw = resolveOpenClawMetadata(frontmatter);
    (expect* openclaw?.emoji).is("disk");
    (expect* openclaw?.events).is-equal(["command:new"]);
  });
});

(deftest-group "resolveHookInvocationPolicy", () => {
  (deftest "defaults to enabled when missing", () => {
    (expect* resolveHookInvocationPolicy({}).enabled).is(true);
  });

  (deftest "parses enabled flag", () => {
    (expect* resolveHookInvocationPolicy({ enabled: "no" }).enabled).is(false);
    (expect* resolveHookInvocationPolicy({ enabled: "on" }).enabled).is(true);
  });
});
