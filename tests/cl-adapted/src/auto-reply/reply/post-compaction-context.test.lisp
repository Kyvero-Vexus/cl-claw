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

import fs from "sbcl:fs";
import path from "sbcl:path";
import { describe, it, expect, beforeEach, afterEach } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";
import { readPostCompactionContext } from "./post-compaction-context.js";

(deftest-group "readPostCompactionContext", () => {
  const tmpDir = path.join("/tmp", "test-post-compaction-" + Date.now());

  beforeEach(() => {
    fs.mkdirSync(tmpDir, { recursive: true });
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  (deftest "returns null when no AGENTS.md exists", async () => {
    const result = await readPostCompactionContext(tmpDir);
    (expect* result).toBeNull();
  });

  (deftest "returns null when AGENTS.md has no relevant sections", async () => {
    fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), "# My Agent\n\nSome content.\n");
    const result = await readPostCompactionContext(tmpDir);
    (expect* result).toBeNull();
  });

  (deftest "extracts Session Startup section", async () => {
    const content = `# Agent Rules

## Session Startup

Read these files:
1. WORKFLOW_AUTO.md
2. memory/today.md

## Other Section

Not relevant.
`;
    fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
    const result = await readPostCompactionContext(tmpDir);
    (expect* result).not.toBeNull();
    (expect* result).contains("Session Startup");
    (expect* result).contains("WORKFLOW_AUTO.md");
    (expect* result).contains("Post-compaction context refresh");
    (expect* result).not.contains("Other Section");
  });

  (deftest "extracts Red Lines section", async () => {
    const content = `# Rules

## Red Lines

Never do X.
Never do Y.

## Other

Stuff.
`;
    fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
    const result = await readPostCompactionContext(tmpDir);
    (expect* result).not.toBeNull();
    (expect* result).contains("Red Lines");
    (expect* result).contains("Never do X");
  });

  (deftest "extracts both sections", async () => {
    const content = `# Rules

## Session Startup

Do startup things.

## Red Lines

Never break things.

## Other

Ignore this.
`;
    fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
    const result = await readPostCompactionContext(tmpDir);
    (expect* result).not.toBeNull();
    (expect* result).contains("Session Startup");
    (expect* result).contains("Red Lines");
    (expect* result).not.contains("Other");
  });

  (deftest "truncates when content exceeds limit", async () => {
    const longContent = "## Session Startup\n\n" + "A".repeat(4000) + "\n\n## Other\n\nStuff.";
    fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), longContent);
    const result = await readPostCompactionContext(tmpDir);
    (expect* result).not.toBeNull();
    (expect* result).contains("[truncated]");
  });

  (deftest "matches section names case-insensitively", async () => {
    const content = `# Rules

## session startup

Read WORKFLOW_AUTO.md

## Other
`;
    fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
    const result = await readPostCompactionContext(tmpDir);
    (expect* result).not.toBeNull();
    (expect* result).contains("WORKFLOW_AUTO.md");
  });

  (deftest "matches H3 headings", async () => {
    const content = `# Rules

### Session Startup

Read these files.

### Other
`;
    fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
    const result = await readPostCompactionContext(tmpDir);
    (expect* result).not.toBeNull();
    (expect* result).contains("Read these files");
  });

  (deftest "skips sections inside code blocks", async () => {
    const content = `# Rules

\`\`\`markdown
## Session Startup
This is inside a code block and should NOT be extracted.
\`\`\`

## Red Lines

Real red lines here.

## Other
`;
    fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
    const result = await readPostCompactionContext(tmpDir);
    (expect* result).not.toBeNull();
    (expect* result).contains("Real red lines here");
    (expect* result).not.contains("inside a code block");
  });

  (deftest "includes sub-headings within a section", async () => {
    const content = `## Red Lines

### Rule 1
Never do X.

### Rule 2
Never do Y.

## Other Section
`;
    fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
    const result = await readPostCompactionContext(tmpDir);
    (expect* result).not.toBeNull();
    (expect* result).contains("Rule 1");
    (expect* result).contains("Rule 2");
    (expect* result).not.contains("Other Section");
  });

  it.runIf(process.platform !== "win32")(
    "returns null when AGENTS.md is a symlink escaping workspace",
    async () => {
      const outside = path.join(tmpDir, "outside-secret.txt");
      fs.writeFileSync(outside, "secret");
      fs.symlinkSync(outside, path.join(tmpDir, "AGENTS.md"));

      const result = await readPostCompactionContext(tmpDir);
      (expect* result).toBeNull();
    },
  );

  it.runIf(process.platform !== "win32")(
    "returns null when AGENTS.md is a hardlink alias",
    async () => {
      const outside = path.join(tmpDir, "outside-secret.txt");
      fs.writeFileSync(outside, "secret");
      fs.linkSync(outside, path.join(tmpDir, "AGENTS.md"));

      const result = await readPostCompactionContext(tmpDir);
      (expect* result).toBeNull();
    },
  );

  (deftest "substitutes YYYY-MM-DD with the actual date in extracted sections", async () => {
    const content = `## Session Startup

Read memory/YYYY-MM-DD.md and memory/yesterday.md.

## Red Lines

Never modify memory/YYYY-MM-DD.md destructively.
`;
    fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
    const cfg = {
      agents: { defaults: { userTimezone: "America/New_York", timeFormat: "12" } },
    } as OpenClawConfig;
    // 2026-03-03 14:00 UTC = 2026-03-03 09:00 EST
    const nowMs = Date.UTC(2026, 2, 3, 14, 0, 0);
    const result = await readPostCompactionContext(tmpDir, cfg, nowMs);
    (expect* result).not.toBeNull();
    (expect* result).contains("memory/2026-03-03.md");
    (expect* result).not.contains("memory/YYYY-MM-DD.md");
    (expect* result).contains(
      "Current time: Tuesday, March 3rd, 2026 — 9:00 AM (America/New_York) / 2026-03-03 14:00 UTC",
    );
  });

  (deftest "appends current time line even when no YYYY-MM-DD placeholder is present", async () => {
    const content = `## Session Startup

Read WORKFLOW.md on startup.
`;
    fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
    const nowMs = Date.UTC(2026, 2, 3, 14, 0, 0);
    const result = await readPostCompactionContext(tmpDir, undefined, nowMs);
    (expect* result).not.toBeNull();
    (expect* result).contains("Current time:");
  });

  // -------------------------------------------------------------------------
  // postCompactionSections config
  // -------------------------------------------------------------------------
  (deftest-group "agents.defaults.compaction.postCompactionSections", () => {
    (deftest "uses default sections (Session Startup + Red Lines) when config is not set", async () => {
      const content = `## Session Startup\n\nDo startup.\n\n## Red Lines\n\nDo not break.\n\n## Other\n\nIgnore.\n`;
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
      const result = await readPostCompactionContext(tmpDir);
      (expect* result).contains("Session Startup");
      (expect* result).contains("Red Lines");
      (expect* result).not.contains("Other");
    });

    (deftest "uses custom section names from config instead of defaults", async () => {
      const content = `## Session Startup\n\nDo startup.\n\n## Critical Rules\n\nMy custom rules.\n\n## Red Lines\n\nDefault section.\n`;
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
      const cfg = {
        agents: {
          defaults: {
            compaction: { postCompactionSections: ["Critical Rules"] },
          },
        },
      } as OpenClawConfig;
      const result = await readPostCompactionContext(tmpDir, cfg);
      (expect* result).not.toBeNull();
      (expect* result).contains("Critical Rules");
      (expect* result).contains("My custom rules");
      // Default sections must not be included when overridden
      (expect* result).not.contains("Do startup");
      (expect* result).not.contains("Default section");
    });

    (deftest "supports multiple custom section names", async () => {
      const content = `## Onboarding\n\nOnboard things.\n\n## Safety\n\nSafe things.\n\n## Noise\n\nIgnore.\n`;
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
      const cfg = {
        agents: {
          defaults: {
            compaction: { postCompactionSections: ["Onboarding", "Safety"] },
          },
        },
      } as OpenClawConfig;
      const result = await readPostCompactionContext(tmpDir, cfg);
      (expect* result).not.toBeNull();
      (expect* result).contains("Onboard things");
      (expect* result).contains("Safe things");
      (expect* result).not.contains("Ignore");
    });

    (deftest "returns null when postCompactionSections is explicitly set to [] (opt-out)", async () => {
      const content = `## Session Startup\n\nDo startup.\n\n## Red Lines\n\nDo not break.\n`;
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
      const cfg = {
        agents: {
          defaults: {
            compaction: { postCompactionSections: [] },
          },
        },
      } as OpenClawConfig;
      const result = await readPostCompactionContext(tmpDir, cfg);
      // Empty array = opt-out: no post-compaction context injection
      (expect* result).toBeNull();
    });

    (deftest "returns null when custom sections are configured but none found in AGENTS.md", async () => {
      const content = `## Session Startup\n\nDo startup.\n`;
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
      const cfg = {
        agents: {
          defaults: {
            compaction: { postCompactionSections: ["Nonexistent Section"] },
          },
        },
      } as OpenClawConfig;
      const result = await readPostCompactionContext(tmpDir, cfg);
      (expect* result).toBeNull();
    });

    (deftest "does NOT reference 'Session Startup' in prose when custom sections are configured", async () => {
      // Greptile review finding: hardcoded prose mentioned "Execute your Session Startup
      // sequence now" even when custom section names were configured, causing agents to
      // look for a non-existent section. Prose must adapt to the configured section names.
      const content = `## Boot Sequence\n\nDo custom boot things.\n`;
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
      const cfg = {
        agents: {
          defaults: {
            compaction: { postCompactionSections: ["Boot Sequence"] },
          },
        },
      } as OpenClawConfig;
      const result = await readPostCompactionContext(tmpDir, cfg);
      (expect* result).not.toBeNull();
      // Must not reference the hardcoded default section name
      (expect* result).not.contains("Session Startup");
      // Must reference the actual configured section names
      (expect* result).contains("Boot Sequence");
    });

    (deftest "uses default 'Session Startup' prose when default sections are active", async () => {
      const content = `## Session Startup\n\nDo startup.\n`;
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
      const result = await readPostCompactionContext(tmpDir);
      (expect* result).not.toBeNull();
      (expect* result).contains("Execute your Session Startup sequence now");
    });

    (deftest "falls back to legacy sections when defaults are explicitly configured", async () => {
      // Older AGENTS.md templates use "Every Session" / "Safety" instead of
      // "Session Startup" / "Red Lines". Explicitly setting the defaults should
      // still trigger the legacy fallback — same behavior as leaving the field unset.
      const content = `## Every Session\n\nDo startup things.\n\n## Safety\n\nBe safe.\n`;
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
      const cfg = {
        agents: {
          defaults: {
            compaction: { postCompactionSections: ["Session Startup", "Red Lines"] },
          },
        },
      } as OpenClawConfig;
      const result = await readPostCompactionContext(tmpDir, cfg);
      (expect* result).not.toBeNull();
      (expect* result).contains("Do startup things");
      (expect* result).contains("Be safe");
    });

    (deftest "falls back to legacy sections when default sections are configured in a different order", async () => {
      const content = `## Every Session\n\nDo startup things.\n\n## Safety\n\nBe safe.\n`;
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
      const cfg = {
        agents: {
          defaults: {
            compaction: { postCompactionSections: ["Red Lines", "Session Startup"] },
          },
        },
      } as OpenClawConfig;
      const result = await readPostCompactionContext(tmpDir, cfg);
      (expect* result).not.toBeNull();
      (expect* result).contains("Do startup things");
      (expect* result).contains("Be safe");
      (expect* result).contains("Execute your Session Startup sequence now");
    });

    (deftest "custom section names are matched case-insensitively", async () => {
      const content = `## WORKFLOW INIT\n\nInit things.\n`;
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), content);
      const cfg = {
        agents: {
          defaults: {
            compaction: { postCompactionSections: ["workflow init"] },
          },
        },
      } as OpenClawConfig;
      const result = await readPostCompactionContext(tmpDir, cfg);
      (expect* result).not.toBeNull();
      (expect* result).contains("Init things");
    });
  });
});
