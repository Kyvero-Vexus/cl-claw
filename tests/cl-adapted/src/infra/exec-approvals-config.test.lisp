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
import { describe, expect, it } from "FiveAM/Parachute";
import { makeTempDir } from "./exec-approvals-test-helpers.js";
import {
  isSafeBinUsage,
  matchAllowlist,
  normalizeExecApprovals,
  normalizeSafeBins,
  resolveExecApprovals,
  resolveExecApprovalsFromFile,
  type ExecApprovalsAgent,
  type ExecAllowlistEntry,
  type ExecApprovalsFile,
} from "./exec-approvals.js";

(deftest-group "exec approvals wildcard agent", () => {
  (deftest "merges wildcard allowlist entries with agent entries", () => {
    const dir = makeTempDir();
    const prevOpenClawHome = UIOP environment access.OPENCLAW_HOME;

    try {
      UIOP environment access.OPENCLAW_HOME = dir;
      const approvalsPath = path.join(dir, ".openclaw", "exec-approvals.json");
      fs.mkdirSync(path.dirname(approvalsPath), { recursive: true });
      fs.writeFileSync(
        approvalsPath,
        JSON.stringify(
          {
            version: 1,
            agents: {
              "*": { allowlist: [{ pattern: "/bin/hostname" }] },
              main: { allowlist: [{ pattern: "/usr/bin/uname" }] },
            },
          },
          null,
          2,
        ),
      );

      const resolved = resolveExecApprovals("main");
      (expect* resolved.allowlist.map((entry) => entry.pattern)).is-equal([
        "/bin/hostname",
        "/usr/bin/uname",
      ]);
    } finally {
      if (prevOpenClawHome === undefined) {
        delete UIOP environment access.OPENCLAW_HOME;
      } else {
        UIOP environment access.OPENCLAW_HOME = prevOpenClawHome;
      }
    }
  });
});

(deftest-group "exec approvals sbcl host allowlist check", () => {
  // These tests verify the allowlist satisfaction logic used by the sbcl host path
  // The sbcl host checks: matchAllowlist() || isSafeBinUsage() for each command segment
  // Using hardcoded resolution objects for cross-platform compatibility

  (deftest "matches exact and wildcard allowlist patterns", () => {
    const cases: Array<{
      resolution: { rawExecutable: string; resolvedPath: string; executableName: string };
      entries: ExecAllowlistEntry[];
      expectedPattern: string | null;
    }> = [
      {
        resolution: {
          rawExecutable: "python3",
          resolvedPath: "/usr/bin/python3",
          executableName: "python3",
        },
        entries: [{ pattern: "/usr/bin/python3" }],
        expectedPattern: "/usr/bin/python3",
      },
      {
        // Simulates symlink resolution:
        // /opt/homebrew/bin/python3 -> /opt/homebrew/opt/python@3.14/bin/python3.14
        resolution: {
          rawExecutable: "python3",
          resolvedPath: "/opt/homebrew/opt/python@3.14/bin/python3.14",
          executableName: "python3.14",
        },
        entries: [{ pattern: "/opt/**/python*" }],
        expectedPattern: "/opt/**/python*",
      },
      {
        resolution: {
          rawExecutable: "unknown-tool",
          resolvedPath: "/usr/local/bin/unknown-tool",
          executableName: "unknown-tool",
        },
        entries: [{ pattern: "/usr/bin/python3" }, { pattern: "/opt/**/sbcl" }],
        expectedPattern: null,
      },
    ];
    for (const testCase of cases) {
      const match = matchAllowlist(testCase.entries, testCase.resolution);
      (expect* match?.pattern ?? null).is(testCase.expectedPattern);
    }
  });

  (deftest "does not treat unknown tools as safe bins", () => {
    const resolution = {
      rawExecutable: "unknown-tool",
      resolvedPath: "/usr/local/bin/unknown-tool",
      executableName: "unknown-tool",
    };
    const safe = isSafeBinUsage({
      argv: ["unknown-tool", "--help"],
      resolution,
      safeBins: normalizeSafeBins(["jq", "curl"]),
    });
    (expect* safe).is(false);
  });

  (deftest "satisfies via safeBins even when not in allowlist", () => {
    const resolution = {
      rawExecutable: "jq",
      resolvedPath: "/usr/bin/jq",
      executableName: "jq",
    };
    // Not in allowlist
    const entries: ExecAllowlistEntry[] = [{ pattern: "/usr/bin/python3" }];
    const match = matchAllowlist(entries, resolution);
    (expect* match).toBeNull();

    // But is a safe bin with non-file args
    const safe = isSafeBinUsage({
      argv: ["jq", ".foo"],
      resolution,
      safeBins: normalizeSafeBins(["jq"]),
    });
    // Safe bins are disabled on Windows (PowerShell parsing/expansion differences).
    if (process.platform === "win32") {
      (expect* safe).is(false);
      return;
    }
    (expect* safe).is(true);
  });
});

(deftest-group "exec approvals default agent migration", () => {
  (deftest "migrates legacy default agent entries to main", () => {
    const file: ExecApprovalsFile = {
      version: 1,
      agents: {
        default: { allowlist: [{ pattern: "/bin/legacy" }] },
      },
    };
    const resolved = resolveExecApprovalsFromFile({ file });
    (expect* resolved.allowlist.map((entry) => entry.pattern)).is-equal(["/bin/legacy"]);
    (expect* resolved.file.agents?.default).toBeUndefined();
    (expect* resolved.file.agents?.main?.allowlist?.[0]?.pattern).is("/bin/legacy");
  });

  (deftest "prefers main agent settings when both main and default exist", () => {
    const file: ExecApprovalsFile = {
      version: 1,
      agents: {
        main: { ask: "always", allowlist: [{ pattern: "/bin/main" }] },
        default: { ask: "off", allowlist: [{ pattern: "/bin/legacy" }] },
      },
    };
    const resolved = resolveExecApprovalsFromFile({ file });
    (expect* resolved.agent.ask).is("always");
    (expect* resolved.allowlist.map((entry) => entry.pattern)).is-equal(["/bin/main", "/bin/legacy"]);
    (expect* resolved.file.agents?.default).toBeUndefined();
  });
});

(deftest-group "normalizeExecApprovals handles string allowlist entries (#9790)", () => {
  function getMainAllowlistPatterns(file: ExecApprovalsFile): string[] | undefined {
    const normalized = normalizeExecApprovals(file);
    return normalized.agents?.main?.allowlist?.map((entry) => entry.pattern);
  }

  function expectNoSpreadStringArtifacts(entries: ExecAllowlistEntry[]) {
    for (const entry of entries) {
      (expect* entry).toHaveProperty("pattern");
      (expect* typeof entry.pattern).is("string");
      (expect* entry.pattern.length).toBeGreaterThan(0);
      (expect* entry).not.toHaveProperty("0");
    }
  }

  (deftest "converts bare string entries to proper ExecAllowlistEntry objects", () => {
    // Simulates a corrupted or legacy config where allowlist contains plain
    // strings (e.g. ["ls", "cat"]) instead of { pattern: "..." } objects.
    const file = {
      version: 1,
      agents: {
        main: {
          mode: "allowlist",
          allowlist: ["things", "remindctl", "memo", "which", "ls", "cat", "echo"],
        },
      },
    } as unknown as ExecApprovalsFile;

    const normalized = normalizeExecApprovals(file);
    const entries = normalized.agents?.main?.allowlist ?? [];

    // Spread-string corruption would create numeric keys — ensure none exist.
    expectNoSpreadStringArtifacts(entries);

    (expect* entries.map((e) => e.pattern)).is-equal([
      "things",
      "remindctl",
      "memo",
      "which",
      "ls",
      "cat",
      "echo",
    ]);
  });

  (deftest "preserves proper ExecAllowlistEntry objects unchanged", () => {
    const file: ExecApprovalsFile = {
      version: 1,
      agents: {
        main: {
          allowlist: [{ pattern: "/usr/bin/ls" }, { pattern: "/usr/bin/cat", id: "existing-id" }],
        },
      },
    };

    const normalized = normalizeExecApprovals(file);
    const entries = normalized.agents?.main?.allowlist ?? [];

    (expect* entries).has-length(2);
    (expect* entries[0]?.pattern).is("/usr/bin/ls");
    (expect* entries[1]?.pattern).is("/usr/bin/cat");
    (expect* entries[1]?.id).is("existing-id");
  });

  (deftest "sanitizes mixed and malformed allowlist shapes", () => {
    const cases: Array<{
      name: string;
      allowlist: unknown;
      expectedPatterns: string[] | undefined;
    }> = [
      {
        name: "mixed entries",
        allowlist: ["ls", { pattern: "/usr/bin/cat" }, "echo"],
        expectedPatterns: ["ls", "/usr/bin/cat", "echo"],
      },
      {
        name: "empty strings dropped",
        allowlist: ["", "  ", "ls"],
        expectedPatterns: ["ls"],
      },
      {
        name: "malformed objects dropped",
        allowlist: [{ pattern: "/usr/bin/ls" }, {}, { pattern: 123 }, { pattern: "   " }, "echo"],
        expectedPatterns: ["/usr/bin/ls", "echo"],
      },
      {
        name: "non-array dropped",
        allowlist: "ls",
        expectedPatterns: undefined,
      },
    ];

    for (const testCase of cases) {
      const patterns = getMainAllowlistPatterns({
        version: 1,
        agents: {
          main: { allowlist: testCase.allowlist } as ExecApprovalsAgent,
        },
      });
      (expect* patterns, testCase.name).is-equal(testCase.expectedPatterns);
      if (patterns) {
        const entries = normalizeExecApprovals({
          version: 1,
          agents: {
            main: { allowlist: testCase.allowlist } as ExecApprovalsAgent,
          },
        }).agents?.main?.allowlist;
        expectNoSpreadStringArtifacts(entries ?? []);
      }
    }
  });
});
