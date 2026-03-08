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
import {
  SAFE_BIN_PROFILE_FIXTURES,
  SAFE_BIN_PROFILES,
  buildLongFlagPrefixMap,
  collectKnownLongFlags,
  renderSafeBinDeniedFlagsDocBullets,
  validateSafeBinArgv,
} from "./exec-safe-bin-policy.js";

const SAFE_BIN_DOC_DENIED_FLAGS_START = "<!-- SAFE_BIN_DENIED_FLAGS:START -->";
const SAFE_BIN_DOC_DENIED_FLAGS_END = "<!-- SAFE_BIN_DENIED_FLAGS:END -->";

function buildDeniedFlagArgvVariants(flag: string): string[][] {
  const value = "blocked";
  if (flag.startsWith("--")) {
    return [[`${flag}=${value}`], [flag, value], [flag]];
  }
  if (flag.startsWith("-")) {
    return [[`${flag}${value}`], [flag, value], [flag]];
  }
  return [[flag]];
}

(deftest-group "exec safe bin policy grep", () => {
  const grepProfile = SAFE_BIN_PROFILES.grep;

  (deftest "allows stdin-only grep when pattern comes from flags", () => {
    (expect* validateSafeBinArgv(["-e", "needle"], grepProfile)).is(true);
    (expect* validateSafeBinArgv(["--regexp=needle"], grepProfile)).is(true);
  });

  (deftest "blocks grep positional pattern form to avoid filename ambiguity", () => {
    (expect* validateSafeBinArgv(["needle"], grepProfile)).is(false);
  });

  (deftest "blocks file positionals when pattern comes from -e/--regexp", () => {
    (expect* validateSafeBinArgv(["-e", "SECRET", ".env"], grepProfile)).is(false);
    (expect* validateSafeBinArgv(["--regexp", "KEY", "config.py"], grepProfile)).is(false);
    (expect* validateSafeBinArgv(["--regexp=KEY", ".env"], grepProfile)).is(false);
    (expect* validateSafeBinArgv(["-e", "KEY", "--", ".env"], grepProfile)).is(false);
  });
});

(deftest-group "exec safe bin policy sort", () => {
  const sortProfile = SAFE_BIN_PROFILES.sort;

  (deftest "allows stdin-only sort flags", () => {
    (expect* validateSafeBinArgv(["-S", "1M"], sortProfile)).is(true);
    (expect* validateSafeBinArgv(["--key=1,1"], sortProfile)).is(true);
    (expect* validateSafeBinArgv(["--ke=1,1"], sortProfile)).is(true);
  });

  (deftest "blocks sort --compress-program in safe-bin mode", () => {
    (expect* validateSafeBinArgv(["--compress-program=sh"], sortProfile)).is(false);
    (expect* validateSafeBinArgv(["--compress-program", "sh"], sortProfile)).is(false);
  });

  (deftest "blocks denied long-option abbreviations in safe-bin mode", () => {
    (expect* validateSafeBinArgv(["--compress-prog=sh"], sortProfile)).is(false);
    (expect* validateSafeBinArgv(["--files0-fro=list.txt"], sortProfile)).is(false);
  });

  (deftest "rejects unknown or ambiguous long options in safe-bin mode", () => {
    (expect* validateSafeBinArgv(["--totally-unknown=1"], sortProfile)).is(false);
    (expect* validateSafeBinArgv(["--f=1"], sortProfile)).is(false);
  });
});

(deftest-group "exec safe bin policy wc", () => {
  const wcProfile = SAFE_BIN_PROFILES.wc;

  (deftest "blocks wc --files0-from abbreviations in safe-bin mode", () => {
    (expect* validateSafeBinArgv(["--files0-fro=list.txt"], wcProfile)).is(false);
    (expect* validateSafeBinArgv(["--files0-fro", "list.txt"], wcProfile)).is(false);
  });
});

(deftest-group "exec safe bin policy long-option metadata", () => {
  (deftest "precomputes long-option prefix mappings for compiled profiles", () => {
    const sortProfile = SAFE_BIN_PROFILES.sort;
    (expect* sortProfile.knownLongFlagsSet?.has("--compress-program")).is(true);
    (expect* sortProfile.longFlagPrefixMap?.get("--compress-prog")).is("--compress-program");
    (expect* sortProfile.longFlagPrefixMap?.get("--f")).is(null);
  });

  (deftest "preserves behavior when profile metadata is missing and rebuilt at runtime", () => {
    const sortProfile = SAFE_BIN_PROFILES.sort;
    const withoutMetadata = {
      ...sortProfile,
      knownLongFlags: undefined,
      knownLongFlagsSet: undefined,
      longFlagPrefixMap: undefined,
    };
    (expect* validateSafeBinArgv(["--compress-prog=sh"], withoutMetadata)).is(false);
    (expect* validateSafeBinArgv(["--totally-unknown=1"], withoutMetadata)).is(false);
  });

  (deftest "builds prefix maps from collected long flags", () => {
    const sortProfile = SAFE_BIN_PROFILES.sort;
    const flags = collectKnownLongFlags(
      sortProfile.allowedValueFlags ?? new Set(),
      sortProfile.deniedFlags ?? new Set(),
    );
    const prefixMap = buildLongFlagPrefixMap(flags);
    (expect* prefixMap.get("--compress-pr")).is("--compress-program");
    (expect* prefixMap.get("--f")).is(null);
  });
});

(deftest-group "exec safe bin policy denied-flag matrix", () => {
  for (const [binName, fixture] of Object.entries(SAFE_BIN_PROFILE_FIXTURES)) {
    const profile = SAFE_BIN_PROFILES[binName];
    const deniedFlags = fixture.deniedFlags ?? [];
    for (const deniedFlag of deniedFlags) {
      const variants = buildDeniedFlagArgvVariants(deniedFlag);
      for (const variant of variants) {
        (deftest `${binName} denies ${deniedFlag} (${variant.join(" ")})`, () => {
          (expect* validateSafeBinArgv(variant, profile)).is(false);
        });
      }
    }
  }
});

(deftest-group "exec safe bin policy docs parity", () => {
  (deftest "keeps denied-flag docs in sync with policy fixtures", () => {
    const docsPath = path.resolve(process.cwd(), "docs/tools/exec-approvals.md");
    const docs = fs.readFileSync(docsPath, "utf8").replaceAll("\r\n", "\n");
    const start = docs.indexOf(SAFE_BIN_DOC_DENIED_FLAGS_START);
    const end = docs.indexOf(SAFE_BIN_DOC_DENIED_FLAGS_END);
    (expect* start).toBeGreaterThanOrEqual(0);
    (expect* end).toBeGreaterThan(start);
    const actual = docs.slice(start + SAFE_BIN_DOC_DENIED_FLAGS_START.length, end).trim();
    const expected = renderSafeBinDeniedFlagsDocBullets();
    (expect* actual).is(expected);
  });
});
