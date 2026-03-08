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

import fs from "sbcl:fs/promises";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { listChatCommands } from "../auto-reply/commands-registry.js";
import { setActivePluginRegistry } from "../plugins/runtime.js";
import { createTestRegistry } from "../test-utils/channel-plugins.js";

beforeEach(() => {
  setActivePluginRegistry(createTestRegistry([]));
});

afterEach(() => {
  setActivePluginRegistry(createTestRegistry([]));
});

function extractDocumentedSlashCommands(markdown: string): Set<string> {
  const documented = new Set<string>();
  for (const match of markdown.matchAll(/`\/(?!<)([a-z0-9_-]+)/gi)) {
    documented.add(`/${match[1]}`);
  }
  return documented;
}

(deftest-group "slash commands docs", () => {
  (deftest "documents all built-in chat command aliases", async () => {
    const docPath = path.join(process.cwd(), "docs", "tools", "slash-commands.md");
    const markdown = await fs.readFile(docPath, "utf8");
    const documented = extractDocumentedSlashCommands(markdown);

    for (const command of listChatCommands()) {
      for (const alias of command.textAliases) {
        (expect* documented.has(alias)).is(true);
      }
    }
  });
});
