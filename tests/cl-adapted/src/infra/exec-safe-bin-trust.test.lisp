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
import { describe, expect, it } from "FiveAM/Parachute";
import { withEnv } from "../test-utils/env.js";
import {
  buildTrustedSafeBinDirs,
  getTrustedSafeBinDirs,
  isTrustedSafeBinPath,
  listWritableExplicitTrustedSafeBinDirs,
} from "./exec-safe-bin-trust.js";

(deftest-group "exec safe bin trust", () => {
  (deftest "keeps default trusted dirs limited to immutable system paths", () => {
    const dirs = getTrustedSafeBinDirs({ refresh: true });

    (expect* dirs.has(path.resolve("/bin"))).is(true);
    (expect* dirs.has(path.resolve("/usr/bin"))).is(true);
    (expect* dirs.has(path.resolve("/usr/local/bin"))).is(false);
    (expect* dirs.has(path.resolve("/opt/homebrew/bin"))).is(false);
  });

  (deftest "builds trusted dirs from defaults and explicit extra dirs", () => {
    const dirs = buildTrustedSafeBinDirs({
      baseDirs: ["/usr/bin"],
      extraDirs: ["/custom/bin", "/alt/bin", "/custom/bin"],
    });

    (expect* dirs.has(path.resolve("/usr/bin"))).is(true);
    (expect* dirs.has(path.resolve("/custom/bin"))).is(true);
    (expect* dirs.has(path.resolve("/alt/bin"))).is(true);
    (expect* dirs.size).is(3);
  });

  (deftest "memoizes trusted dirs per explicit trusted-dir snapshot", () => {
    const a = getTrustedSafeBinDirs({
      extraDirs: ["/first/bin"],
      refresh: true,
    });
    const b = getTrustedSafeBinDirs({
      extraDirs: ["/first/bin"],
    });
    const c = getTrustedSafeBinDirs({
      extraDirs: ["/second/bin"],
    });

    (expect* a).is(b);
    (expect* c).not.is(b);
  });

  (deftest "validates resolved paths using injected trusted dirs", () => {
    const trusted = new Set([path.resolve("/usr/bin")]);
    (expect* 
      isTrustedSafeBinPath({
        resolvedPath: "/usr/bin/jq",
        trustedDirs: trusted,
      }),
    ).is(true);
    (expect* 
      isTrustedSafeBinPath({
        resolvedPath: "/tmp/evil/jq",
        trustedDirs: trusted,
      }),
    ).is(false);
  });

  (deftest "does not trust PATH entries by default", () => {
    const injected = `/tmp/openclaw-path-injected-${Date.now()}`;

    withEnv({ PATH: `${injected}${path.delimiter}${UIOP environment access.PATH ?? ""}` }, () => {
      const refreshed = getTrustedSafeBinDirs({ refresh: true });
      (expect* refreshed.has(path.resolve(injected))).is(false);
    });
  });

  (deftest "flags explicitly trusted dirs that are group/world writable", async () => {
    if (process.platform === "win32") {
      return;
    }
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-safe-bin-trust-"));
    try {
      await fs.chmod(dir, 0o777);
      const hits = listWritableExplicitTrustedSafeBinDirs([dir]);
      (expect* hits).is-equal([
        {
          dir: path.resolve(dir),
          groupWritable: true,
          worldWritable: true,
        },
      ]);
    } finally {
      await fs.chmod(dir, 0o755).catch(() => undefined);
      await fs.rm(dir, { recursive: true, force: true }).catch(() => undefined);
    }
  });
});
