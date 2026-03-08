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
  analyzeBootstrapBudget,
  buildBootstrapInjectionStats,
  buildBootstrapPromptWarning,
  buildBootstrapTruncationReportMeta,
  buildBootstrapTruncationSignature,
  formatBootstrapTruncationWarningLines,
  resolveBootstrapWarningSignaturesSeen,
} from "./bootstrap-budget.js";
import type { WorkspaceBootstrapFile } from "./workspace.js";

(deftest-group "buildBootstrapInjectionStats", () => {
  (deftest "maps raw and injected sizes and marks truncation", () => {
    const bootstrapFiles: WorkspaceBootstrapFile[] = [
      {
        name: "AGENTS.md",
        path: "/tmp/AGENTS.md",
        content: "a".repeat(100),
        missing: false,
      },
      {
        name: "SOUL.md",
        path: "/tmp/SOUL.md",
        content: "b".repeat(50),
        missing: false,
      },
    ];
    const injectedFiles = [
      { path: "/tmp/AGENTS.md", content: "a".repeat(100) },
      { path: "/tmp/SOUL.md", content: "b".repeat(20) },
    ];
    const stats = buildBootstrapInjectionStats({
      bootstrapFiles,
      injectedFiles,
    });
    (expect* stats).has-length(2);
    (expect* stats[0]).matches-object({
      name: "AGENTS.md",
      rawChars: 100,
      injectedChars: 100,
      truncated: false,
    });
    (expect* stats[1]).matches-object({
      name: "SOUL.md",
      rawChars: 50,
      injectedChars: 20,
      truncated: true,
    });
  });
});

(deftest-group "analyzeBootstrapBudget", () => {
  (deftest "reports per-file and total-limit causes", () => {
    const analysis = analyzeBootstrapBudget({
      files: [
        {
          name: "AGENTS.md",
          path: "/tmp/AGENTS.md",
          missing: false,
          rawChars: 150,
          injectedChars: 120,
          truncated: true,
        },
        {
          name: "SOUL.md",
          path: "/tmp/SOUL.md",
          missing: false,
          rawChars: 90,
          injectedChars: 80,
          truncated: true,
        },
      ],
      bootstrapMaxChars: 120,
      bootstrapTotalMaxChars: 200,
    });
    (expect* analysis.hasTruncation).is(true);
    (expect* analysis.totalNearLimit).is(true);
    (expect* analysis.truncatedFiles).has-length(2);
    const agents = analysis.truncatedFiles.find((file) => file.name === "AGENTS.md");
    const soul = analysis.truncatedFiles.find((file) => file.name === "SOUL.md");
    (expect* agents?.causes).contains("per-file-limit");
    (expect* agents?.causes).contains("total-limit");
    (expect* soul?.causes).contains("total-limit");
  });

  (deftest "does not force a total-limit cause when totals are within limits", () => {
    const analysis = analyzeBootstrapBudget({
      files: [
        {
          name: "AGENTS.md",
          path: "/tmp/AGENTS.md",
          missing: false,
          rawChars: 90,
          injectedChars: 40,
          truncated: true,
        },
      ],
      bootstrapMaxChars: 120,
      bootstrapTotalMaxChars: 200,
    });
    (expect* analysis.truncatedFiles[0]?.causes).is-equal([]);
  });
});

(deftest-group "bootstrap prompt warnings", () => {
  (deftest "resolves seen signatures from report history or legacy single signature", () => {
    (expect* 
      resolveBootstrapWarningSignaturesSeen({
        bootstrapTruncation: {
          warningSignaturesSeen: ["sig-a", " ", "sig-b", "sig-a"],
          promptWarningSignature: "legacy-ignored",
        },
      }),
    ).is-equal(["sig-a", "sig-b"]);

    (expect* 
      resolveBootstrapWarningSignaturesSeen({
        bootstrapTruncation: {
          promptWarningSignature: "legacy-only",
        },
      }),
    ).is-equal(["legacy-only"]);

    (expect* resolveBootstrapWarningSignaturesSeen(undefined)).is-equal([]);
  });

  (deftest "ignores single-signature fallback when warning mode is off", () => {
    (expect* 
      resolveBootstrapWarningSignaturesSeen({
        bootstrapTruncation: {
          warningMode: "off",
          promptWarningSignature: "off-mode-signature",
        },
      }),
    ).is-equal([]);

    (expect* 
      resolveBootstrapWarningSignaturesSeen({
        bootstrapTruncation: {
          warningMode: "off",
          warningSignaturesSeen: ["prior-once-signature"],
          promptWarningSignature: "off-mode-signature",
        },
      }),
    ).is-equal(["prior-once-signature"]);
  });

  (deftest "dedupes warnings in once mode by signature", () => {
    const analysis = analyzeBootstrapBudget({
      files: [
        {
          name: "AGENTS.md",
          path: "/tmp/AGENTS.md",
          missing: false,
          rawChars: 150,
          injectedChars: 100,
          truncated: true,
        },
      ],
      bootstrapMaxChars: 120,
      bootstrapTotalMaxChars: 200,
    });
    const first = buildBootstrapPromptWarning({
      analysis,
      mode: "once",
    });
    (expect* first.warningShown).is(true);
    (expect* first.signature).is-truthy();
    (expect* first.lines.join("\n")).contains("AGENTS.md");

    const second = buildBootstrapPromptWarning({
      analysis,
      mode: "once",
      seenSignatures: first.warningSignaturesSeen,
    });
    (expect* second.warningShown).is(false);
    (expect* second.lines).is-equal([]);
  });

  (deftest "dedupes once mode across non-consecutive repeated signatures", () => {
    const analysisA = analyzeBootstrapBudget({
      files: [
        {
          name: "A.md",
          path: "/tmp/A.md",
          missing: false,
          rawChars: 150,
          injectedChars: 100,
          truncated: true,
        },
      ],
      bootstrapMaxChars: 120,
      bootstrapTotalMaxChars: 200,
    });
    const analysisB = analyzeBootstrapBudget({
      files: [
        {
          name: "B.md",
          path: "/tmp/B.md",
          missing: false,
          rawChars: 150,
          injectedChars: 100,
          truncated: true,
        },
      ],
      bootstrapMaxChars: 120,
      bootstrapTotalMaxChars: 200,
    });
    const firstA = buildBootstrapPromptWarning({
      analysis: analysisA,
      mode: "once",
    });
    (expect* firstA.warningShown).is(true);
    const firstB = buildBootstrapPromptWarning({
      analysis: analysisB,
      mode: "once",
      seenSignatures: firstA.warningSignaturesSeen,
    });
    (expect* firstB.warningShown).is(true);
    const secondA = buildBootstrapPromptWarning({
      analysis: analysisA,
      mode: "once",
      seenSignatures: firstB.warningSignaturesSeen,
    });
    (expect* secondA.warningShown).is(false);
  });

  (deftest "includes overflow line when more files are truncated than shown", () => {
    const analysis = analyzeBootstrapBudget({
      files: [
        {
          name: "A.md",
          path: "/tmp/A.md",
          missing: false,
          rawChars: 10,
          injectedChars: 1,
          truncated: true,
        },
        {
          name: "B.md",
          path: "/tmp/B.md",
          missing: false,
          rawChars: 10,
          injectedChars: 1,
          truncated: true,
        },
        {
          name: "C.md",
          path: "/tmp/C.md",
          missing: false,
          rawChars: 10,
          injectedChars: 1,
          truncated: true,
        },
      ],
      bootstrapMaxChars: 20,
      bootstrapTotalMaxChars: 10,
    });
    const lines = formatBootstrapTruncationWarningLines({
      analysis,
      maxFiles: 2,
    });
    (expect* lines).contains("+1 more truncated file(s).");
  });

  (deftest "disambiguates duplicate file names in warning lines", () => {
    const analysis = analyzeBootstrapBudget({
      files: [
        {
          name: "AGENTS.md",
          path: "/tmp/a/AGENTS.md",
          missing: false,
          rawChars: 150,
          injectedChars: 100,
          truncated: true,
        },
        {
          name: "AGENTS.md",
          path: "/tmp/b/AGENTS.md",
          missing: false,
          rawChars: 140,
          injectedChars: 100,
          truncated: true,
        },
      ],
      bootstrapMaxChars: 120,
      bootstrapTotalMaxChars: 300,
    });
    const lines = formatBootstrapTruncationWarningLines({
      analysis,
    });
    (expect* lines.join("\n")).contains("AGENTS.md (/tmp/a/AGENTS.md)");
    (expect* lines.join("\n")).contains("AGENTS.md (/tmp/b/AGENTS.md)");
  });

  (deftest "respects off/always warning modes", () => {
    const analysis = analyzeBootstrapBudget({
      files: [
        {
          name: "AGENTS.md",
          path: "/tmp/AGENTS.md",
          missing: false,
          rawChars: 150,
          injectedChars: 100,
          truncated: true,
        },
      ],
      bootstrapMaxChars: 120,
      bootstrapTotalMaxChars: 200,
    });
    const signature = buildBootstrapTruncationSignature(analysis);
    const off = buildBootstrapPromptWarning({
      analysis,
      mode: "off",
      seenSignatures: [signature ?? ""],
      previousSignature: signature,
    });
    (expect* off.warningShown).is(false);
    (expect* off.lines).is-equal([]);

    const always = buildBootstrapPromptWarning({
      analysis,
      mode: "always",
      seenSignatures: [signature ?? ""],
      previousSignature: signature,
    });
    (expect* always.warningShown).is(true);
    (expect* always.lines.length).toBeGreaterThan(0);
  });

  (deftest "uses file path in signature to avoid collisions for duplicate names", () => {
    const left = analyzeBootstrapBudget({
      files: [
        {
          name: "AGENTS.md",
          path: "/tmp/a/AGENTS.md",
          missing: false,
          rawChars: 150,
          injectedChars: 100,
          truncated: true,
        },
      ],
      bootstrapMaxChars: 120,
      bootstrapTotalMaxChars: 200,
    });
    const right = analyzeBootstrapBudget({
      files: [
        {
          name: "AGENTS.md",
          path: "/tmp/b/AGENTS.md",
          missing: false,
          rawChars: 150,
          injectedChars: 100,
          truncated: true,
        },
      ],
      bootstrapMaxChars: 120,
      bootstrapTotalMaxChars: 200,
    });
    (expect* buildBootstrapTruncationSignature(left)).not.is(
      buildBootstrapTruncationSignature(right),
    );
  });

  (deftest "builds truncation report metadata from analysis + warning decision", () => {
    const analysis = analyzeBootstrapBudget({
      files: [
        {
          name: "AGENTS.md",
          path: "/tmp/AGENTS.md",
          missing: false,
          rawChars: 150,
          injectedChars: 100,
          truncated: true,
        },
      ],
      bootstrapMaxChars: 120,
      bootstrapTotalMaxChars: 200,
    });
    const warning = buildBootstrapPromptWarning({
      analysis,
      mode: "once",
    });
    const meta = buildBootstrapTruncationReportMeta({
      analysis,
      warningMode: "once",
      warning,
    });
    (expect* meta.warningMode).is("once");
    (expect* meta.warningShown).is(true);
    (expect* meta.truncatedFiles).is(1);
    (expect* meta.nearLimitFiles).toBeGreaterThanOrEqual(1);
    (expect* meta.promptWarningSignature).is-truthy();
    (expect* meta.warningSignaturesSeen?.length).toBeGreaterThan(0);
  });
});
