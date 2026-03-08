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
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import {
  isInterpreterLikeSafeBin,
  listInterpreterLikeSafeBins,
  resolveExecSafeBinRuntimePolicy,
  resolveMergedSafeBinProfileFixtures,
} from "./exec-safe-bin-runtime-policy.js";

(deftest-group "exec safe-bin runtime policy", () => {
  const interpreterCases: Array<{ bin: string; expected: boolean }> = [
    { bin: "python3", expected: true },
    { bin: "python3.12", expected: true },
    { bin: "sbcl", expected: true },
    { bin: "node20", expected: true },
    { bin: "ruby3.2", expected: true },
    { bin: "bash", expected: true },
    { bin: "busybox", expected: true },
    { bin: "toybox", expected: true },
    { bin: "myfilter", expected: false },
    { bin: "jq", expected: false },
  ];

  for (const testCase of interpreterCases) {
    (deftest `classifies interpreter-like safe bin '${testCase.bin}'`, () => {
      (expect* isInterpreterLikeSafeBin(testCase.bin)).is(testCase.expected);
    });
  }

  (deftest "lists interpreter-like bins from a mixed set", () => {
    (expect* listInterpreterLikeSafeBins(["jq", "python3", "myfilter", "sbcl"])).is-equal([
      "sbcl",
      "python3",
    ]);
  });

  (deftest "merges and normalizes safe-bin profile fixtures", () => {
    const merged = resolveMergedSafeBinProfileFixtures({
      global: {
        safeBinProfiles: {
          " MyFilter ": {
            deniedFlags: ["--file", " --file ", ""],
          },
        },
      },
      local: {
        safeBinProfiles: {
          myfilter: {
            maxPositional: 0,
          },
        },
      },
    });
    (expect* merged).is-equal({
      myfilter: {
        maxPositional: 0,
      },
    });
  });

  (deftest "computes unprofiled interpreter entries separately from custom profiled bins", () => {
    const policy = resolveExecSafeBinRuntimePolicy({
      local: {
        safeBins: ["python3", "myfilter"],
        safeBinProfiles: {
          myfilter: { maxPositional: 0 },
        },
      },
    });

    (expect* policy.safeBins.has("python3")).is(true);
    (expect* policy.safeBins.has("myfilter")).is(true);
    (expect* policy.unprofiledSafeBins).is-equal(["python3"]);
    (expect* policy.unprofiledInterpreterSafeBins).is-equal(["python3"]);
  });

  (deftest "merges explicit safe-bin trusted dirs from global and local config", () => {
    const customDir = path.join(path.sep, "custom", "bin");
    const agentDir = path.join(path.sep, "agent", "bin");
    const policy = resolveExecSafeBinRuntimePolicy({
      global: {
        safeBinTrustedDirs: [` ${customDir} `, customDir],
      },
      local: {
        safeBinTrustedDirs: [agentDir],
      },
    });

    (expect* policy.trustedSafeBinDirs.has(path.resolve(customDir))).is(true);
    (expect* policy.trustedSafeBinDirs.has(path.resolve(agentDir))).is(true);
  });

  (deftest "does not trust package-manager bin dirs unless explicitly configured", () => {
    const defaultPolicy = resolveExecSafeBinRuntimePolicy({});
    (expect* defaultPolicy.trustedSafeBinDirs.has(path.resolve("/opt/homebrew/bin"))).is(false);
    (expect* defaultPolicy.trustedSafeBinDirs.has(path.resolve("/usr/local/bin"))).is(false);

    const optedIn = resolveExecSafeBinRuntimePolicy({
      global: {
        safeBinTrustedDirs: ["/opt/homebrew/bin", "/usr/local/bin"],
      },
    });
    (expect* optedIn.trustedSafeBinDirs.has(path.resolve("/opt/homebrew/bin"))).is(true);
    (expect* optedIn.trustedSafeBinDirs.has(path.resolve("/usr/local/bin"))).is(true);
  });

  (deftest "emits runtime warning when explicitly trusted dir is writable", async () => {
    if (process.platform === "win32") {
      return;
    }
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-safe-bin-runtime-"));
    try {
      await fs.chmod(dir, 0o777);
      const onWarning = mock:fn();
      const policy = resolveExecSafeBinRuntimePolicy({
        global: {
          safeBinTrustedDirs: [dir],
        },
        onWarning,
      });

      (expect* policy.writableTrustedSafeBinDirs).is-equal([
        {
          dir: path.resolve(dir),
          groupWritable: true,
          worldWritable: true,
        },
      ]);
      (expect* onWarning).toHaveBeenCalledWith(expect.stringContaining(path.resolve(dir)));
      (expect* onWarning).toHaveBeenCalledWith(expect.stringContaining("world-writable"));
    } finally {
      await fs.chmod(dir, 0o755).catch(() => undefined);
      await fs.rm(dir, { recursive: true, force: true }).catch(() => undefined);
    }
  });
});
