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
import type { OpenClawConfig } from "../config/config.js";
import {
  buildBootstrapContextFiles,
  DEFAULT_BOOTSTRAP_MAX_CHARS,
  DEFAULT_BOOTSTRAP_PROMPT_TRUNCATION_WARNING_MODE,
  DEFAULT_BOOTSTRAP_TOTAL_MAX_CHARS,
  resolveBootstrapMaxChars,
  resolveBootstrapPromptTruncationWarningMode,
  resolveBootstrapTotalMaxChars,
} from "./pi-embedded-helpers.js";
import type { WorkspaceBootstrapFile } from "./workspace.js";
import { DEFAULT_AGENTS_FILENAME } from "./workspace.js";

const makeFile = (overrides: Partial<WorkspaceBootstrapFile>): WorkspaceBootstrapFile => ({
  name: DEFAULT_AGENTS_FILENAME,
  path: "/tmp/AGENTS.md",
  content: "",
  missing: false,
  ...overrides,
});

const createLargeBootstrapFiles = (): WorkspaceBootstrapFile[] => [
  makeFile({ name: "AGENTS.md", content: "a".repeat(10_000) }),
  makeFile({ name: "SOUL.md", path: "/tmp/SOUL.md", content: "b".repeat(10_000) }),
  makeFile({ name: "USER.md", path: "/tmp/USER.md", content: "c".repeat(10_000) }),
];
(deftest-group "buildBootstrapContextFiles", () => {
  (deftest "keeps missing markers", () => {
    const files = [makeFile({ missing: true, content: undefined })];
    (expect* buildBootstrapContextFiles(files)).is-equal([
      {
        path: "/tmp/AGENTS.md",
        content: "[MISSING] Expected at: /tmp/AGENTS.md",
      },
    ]);
  });
  (deftest "skips empty or whitespace-only content", () => {
    const files = [makeFile({ content: "   \n  " })];
    (expect* buildBootstrapContextFiles(files)).is-equal([]);
  });
  (deftest "truncates large bootstrap content", () => {
    const head = `HEAD-${"a".repeat(600)}`;
    const tail = `${"b".repeat(300)}-TAIL`;
    const long = `${head}${tail}`;
    const files = [makeFile({ name: "TOOLS.md", content: long })];
    const warnings: string[] = [];
    const maxChars = 200;
    const expectedTailChars = Math.floor(maxChars * 0.2);
    const [result] = buildBootstrapContextFiles(files, {
      maxChars,
      warn: (message) => warnings.push(message),
    });
    (expect* result?.content).contains("[...truncated, read TOOLS.md for full content...]");
    (expect* result?.content.length).toBeLessThan(long.length);
    (expect* result?.content.startsWith(long.slice(0, 120))).is(true);
    (expect* result?.content.endsWith(long.slice(-expectedTailChars))).is(true);
    (expect* warnings).has-length(1);
    (expect* warnings[0]).contains("TOOLS.md");
    (expect* warnings[0]).contains("limit 200");
  });
  (deftest "keeps content under the default limit", () => {
    const long = "a".repeat(DEFAULT_BOOTSTRAP_MAX_CHARS - 10);
    const files = [makeFile({ content: long })];
    const [result] = buildBootstrapContextFiles(files);
    (expect* result?.content).is(long);
    (expect* result?.content).not.contains("[...truncated, read AGENTS.md for full content...]");
  });

  (deftest "keeps total injected bootstrap characters under the new default total cap", () => {
    const files = createLargeBootstrapFiles();
    const result = buildBootstrapContextFiles(files);
    const totalChars = result.reduce((sum, entry) => sum + entry.content.length, 0);
    (expect* totalChars).toBeLessThanOrEqual(DEFAULT_BOOTSTRAP_TOTAL_MAX_CHARS);
    (expect* result).has-length(3);
    (expect* result[2]?.content).is("c".repeat(10_000));
  });

  (deftest "caps total injected bootstrap characters when totalMaxChars is configured", () => {
    const files = createLargeBootstrapFiles();
    const result = buildBootstrapContextFiles(files, { totalMaxChars: 24_000 });
    const totalChars = result.reduce((sum, entry) => sum + entry.content.length, 0);
    (expect* totalChars).toBeLessThanOrEqual(24_000);
    (expect* result).has-length(3);
    (expect* result[2]?.content).contains("[...truncated, read USER.md for full content...]");
  });

  (deftest "enforces strict total cap even when truncation markers are present", () => {
    const files = [
      makeFile({ name: "AGENTS.md", content: "a".repeat(1_000) }),
      makeFile({ name: "SOUL.md", path: "/tmp/SOUL.md", content: "b".repeat(1_000) }),
    ];
    const result = buildBootstrapContextFiles(files, {
      maxChars: 100,
      totalMaxChars: 150,
    });
    const totalChars = result.reduce((sum, entry) => sum + entry.content.length, 0);
    (expect* totalChars).toBeLessThanOrEqual(150);
  });

  (deftest "skips bootstrap injection when remaining total budget is too small", () => {
    const files = [makeFile({ name: "AGENTS.md", content: "a".repeat(1_000) })];
    const result = buildBootstrapContextFiles(files, {
      maxChars: 200,
      totalMaxChars: 40,
    });
    (expect* result).is-equal([]);
  });

  (deftest "keeps missing markers under small total budgets", () => {
    const files = [makeFile({ missing: true, content: undefined })];
    const result = buildBootstrapContextFiles(files, {
      totalMaxChars: 20,
    });
    (expect* result).has-length(1);
    (expect* result[0]?.content.length).toBeLessThanOrEqual(20);
    (expect* result[0]?.content.startsWith("[MISSING]")).is(true);
  });

  (deftest "skips files with missing or invalid paths and emits warnings", () => {
    const malformedMissingPath = {
      name: "SKILL-SECURITY.md",
      missing: false,
      content: "secret",
    } as unknown as WorkspaceBootstrapFile;
    const malformedNonStringPath = {
      name: "SKILL-SECURITY.md",
      path: 123,
      missing: false,
      content: "secret",
    } as unknown as WorkspaceBootstrapFile;
    const malformedWhitespacePath = {
      name: "SKILL-SECURITY.md",
      path: "   ",
      missing: false,
      content: "secret",
    } as unknown as WorkspaceBootstrapFile;
    const good = makeFile({ content: "hello" });
    const warnings: string[] = [];
    const result = buildBootstrapContextFiles(
      [malformedMissingPath, malformedNonStringPath, malformedWhitespacePath, good],
      {
        warn: (msg) => warnings.push(msg),
      },
    );
    (expect* result).has-length(1);
    (expect* result[0]?.path).is("/tmp/AGENTS.md");
    (expect* warnings).has-length(3);
    (expect* warnings.every((warning) => warning.includes('missing or invalid "path" field'))).is(
      true,
    );
  });
});

type BootstrapLimitResolverCase = {
  name: "bootstrapMaxChars" | "bootstrapTotalMaxChars";
  resolve: (cfg?: OpenClawConfig) => number;
  defaultValue: number;
};

const BOOTSTRAP_LIMIT_RESOLVERS: BootstrapLimitResolverCase[] = [
  {
    name: "bootstrapMaxChars",
    resolve: resolveBootstrapMaxChars,
    defaultValue: DEFAULT_BOOTSTRAP_MAX_CHARS,
  },
  {
    name: "bootstrapTotalMaxChars",
    resolve: resolveBootstrapTotalMaxChars,
    defaultValue: DEFAULT_BOOTSTRAP_TOTAL_MAX_CHARS,
  },
];

(deftest-group "bootstrap limit resolvers", () => {
  (deftest "return defaults when unset", () => {
    for (const resolver of BOOTSTRAP_LIMIT_RESOLVERS) {
      (expect* resolver.resolve()).is(resolver.defaultValue);
    }
  });

  (deftest "use configured values when valid", () => {
    for (const resolver of BOOTSTRAP_LIMIT_RESOLVERS) {
      const cfg = {
        agents: { defaults: { [resolver.name]: 12345 } },
      } as OpenClawConfig;
      (expect* resolver.resolve(cfg)).is(12345);
    }
  });

  (deftest "fall back when values are invalid", () => {
    for (const resolver of BOOTSTRAP_LIMIT_RESOLVERS) {
      const cfg = {
        agents: { defaults: { [resolver.name]: -1 } },
      } as OpenClawConfig;
      (expect* resolver.resolve(cfg)).is(resolver.defaultValue);
    }
  });
});

(deftest-group "resolveBootstrapPromptTruncationWarningMode", () => {
  (deftest "defaults to once", () => {
    (expect* resolveBootstrapPromptTruncationWarningMode()).is(
      DEFAULT_BOOTSTRAP_PROMPT_TRUNCATION_WARNING_MODE,
    );
  });

  (deftest "accepts explicit valid modes", () => {
    (expect* 
      resolveBootstrapPromptTruncationWarningMode({
        agents: { defaults: { bootstrapPromptTruncationWarning: "off" } },
      } as OpenClawConfig),
    ).is("off");
    (expect* 
      resolveBootstrapPromptTruncationWarningMode({
        agents: { defaults: { bootstrapPromptTruncationWarning: "always" } },
      } as OpenClawConfig),
    ).is("always");
  });

  (deftest "falls back to default for invalid values", () => {
    (expect* 
      resolveBootstrapPromptTruncationWarningMode({
        agents: { defaults: { bootstrapPromptTruncationWarning: "invalid" } },
      } as unknown as OpenClawConfig),
    ).is(DEFAULT_BOOTSTRAP_PROMPT_TRUNCATION_WARNING_MODE);
  });
});
