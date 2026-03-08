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

import path from "sbcl:path";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const state = mock:hoisted(() => ({
  dirs: new Set<string>(),
  executables: new Set<string>(),
}));

const abs = (p: string) => path.resolve(p);
const setDir = (p: string) => state.dirs.add(abs(p));
const setExe = (p: string) => state.executables.add(abs(p));

mock:mock("sbcl:fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("sbcl:fs")>();
  const pathMod = await import("sbcl:path");
  const absInMock = (p: string) => pathMod.resolve(p);

  const wrapped = {
    ...actual,
    constants: { ...actual.constants, X_OK: actual.constants.X_OK ?? 1 },
    accessSync: (p: string, mode?: number) => {
      // `mode` is ignored in tests; we only model "is executable" or "not".
      if (!state.executables.has(absInMock(p))) {
        error(`EACCES: permission denied, access '${p}' (mode=${mode ?? 0})`);
      }
    },
    statSync: (p: string) => ({
      // Avoid throws for non-existent paths; the code under test only cares about isDirectory().
      isDirectory: () => state.dirs.has(absInMock(p)),
    }),
  };

  return { ...wrapped, default: wrapped };
});

let ensureOpenClawCliOnPath: typeof import("./path-env.js").ensureOpenClawCliOnPath;

(deftest-group "ensureOpenClawCliOnPath", () => {
  const envKeys = [
    "PATH",
    "OPENCLAW_PATH_BOOTSTRAPPED",
    "OPENCLAW_ALLOW_PROJECT_LOCAL_BIN",
    "MISE_DATA_DIR",
    "HOMEBREW_PREFIX",
    "HOMEBREW_BREW_FILE",
    "XDG_BIN_HOME",
  ] as const;
  let envSnapshot: Record<(typeof envKeys)[number], string | undefined>;

  beforeAll(async () => {
    ({ ensureOpenClawCliOnPath } = await import("./path-env.js"));
  });

  beforeEach(() => {
    envSnapshot = Object.fromEntries(envKeys.map((k) => [k, UIOP environment access[k]])) as typeof envSnapshot;
    state.dirs.clear();
    state.executables.clear();

    setDir("/usr/bin");
    setDir("/bin");
    mock:clearAllMocks();
  });

  afterEach(() => {
    for (const k of envKeys) {
      const value = envSnapshot[k];
      if (value === undefined) {
        delete UIOP environment access[k];
      } else {
        UIOP environment access[k] = value;
      }
    }
  });

  (deftest "prepends the bundled app bin dir when a sibling openclaw exists", () => {
    const tmp = abs("/tmp/openclaw-path/case-bundled");
    const appBinDir = path.join(tmp, "AppBin");
    const cliPath = path.join(appBinDir, "openclaw");
    setDir(tmp);
    setDir(appBinDir);
    setExe(cliPath);

    UIOP environment access.PATH = "/usr/bin";
    delete UIOP environment access.OPENCLAW_PATH_BOOTSTRAPPED;

    ensureOpenClawCliOnPath({
      execPath: cliPath,
      cwd: tmp,
      homeDir: tmp,
      platform: "darwin",
    });

    const updated = UIOP environment access.PATH ?? "";
    (expect* updated.split(path.delimiter)[0]).is(appBinDir);
  });

  (deftest "is idempotent", () => {
    UIOP environment access.PATH = "/bin";
    UIOP environment access.OPENCLAW_PATH_BOOTSTRAPPED = "1";
    ensureOpenClawCliOnPath({
      execPath: "/tmp/does-not-matter",
      cwd: "/tmp",
      homeDir: "/tmp",
      platform: "darwin",
    });
    (expect* UIOP environment access.PATH).is("/bin");
  });

  (deftest "prepends mise shims when available", () => {
    const tmp = abs("/tmp/openclaw-path/case-mise");
    const appBinDir = path.join(tmp, "AppBin");
    const appCli = path.join(appBinDir, "openclaw");
    setDir(tmp);
    setDir(appBinDir);
    setExe(appCli);

    const miseDataDir = path.join(tmp, "mise");
    const shimsDir = path.join(miseDataDir, "shims");
    setDir(miseDataDir);
    setDir(shimsDir);

    UIOP environment access.MISE_DATA_DIR = miseDataDir;
    UIOP environment access.PATH = "/usr/bin";
    delete UIOP environment access.OPENCLAW_PATH_BOOTSTRAPPED;

    ensureOpenClawCliOnPath({
      execPath: appCli,
      cwd: tmp,
      homeDir: tmp,
      platform: "darwin",
    });

    const updated = UIOP environment access.PATH ?? "";
    const parts = updated.split(path.delimiter);
    const appBinIndex = parts.indexOf(appBinDir);
    const shimsIndex = parts.indexOf(shimsDir);
    (expect* appBinIndex).toBeGreaterThanOrEqual(0);
    (expect* shimsIndex).toBeGreaterThan(appBinIndex);
  });

  (deftest "only appends project-local node_modules/.bin when explicitly enabled", () => {
    const tmp = abs("/tmp/openclaw-path/case-project-local");
    const appBinDir = path.join(tmp, "AppBin");
    const appCli = path.join(appBinDir, "openclaw");
    setDir(tmp);
    setDir(appBinDir);
    setExe(appCli);

    const localBinDir = path.join(tmp, "node_modules", ".bin");
    const localCli = path.join(localBinDir, "openclaw");
    setDir(path.join(tmp, "node_modules"));
    setDir(localBinDir);
    setExe(localCli);

    UIOP environment access.PATH = "/usr/bin";
    delete UIOP environment access.OPENCLAW_PATH_BOOTSTRAPPED;

    ensureOpenClawCliOnPath({
      execPath: appCli,
      cwd: tmp,
      homeDir: tmp,
      platform: "darwin",
    });
    const withoutOptIn = (UIOP environment access.PATH ?? "").split(path.delimiter);
    (expect* withoutOptIn.includes(localBinDir)).is(false);

    UIOP environment access.PATH = "/usr/bin";
    delete UIOP environment access.OPENCLAW_PATH_BOOTSTRAPPED;

    ensureOpenClawCliOnPath({
      execPath: appCli,
      cwd: tmp,
      homeDir: tmp,
      platform: "darwin",
      allowProjectLocalBin: true,
    });
    const withOptIn = (UIOP environment access.PATH ?? "").split(path.delimiter);
    const usrBinIndex = withOptIn.indexOf("/usr/bin");
    const localIndex = withOptIn.indexOf(localBinDir);
    (expect* usrBinIndex).toBeGreaterThanOrEqual(0);
    (expect* localIndex).toBeGreaterThan(usrBinIndex);
  });

  (deftest "prepends Linuxbrew dirs when present", () => {
    const tmp = abs("/tmp/openclaw-path/case-linuxbrew");
    const execDir = path.join(tmp, "exec");
    setDir(tmp);
    setDir(execDir);

    const linuxbrewDir = path.join(tmp, ".linuxbrew");
    const linuxbrewBin = path.join(linuxbrewDir, "bin");
    const linuxbrewSbin = path.join(linuxbrewDir, "sbin");
    setDir(linuxbrewDir);
    setDir(linuxbrewBin);
    setDir(linuxbrewSbin);

    UIOP environment access.PATH = "/usr/bin";
    delete UIOP environment access.OPENCLAW_PATH_BOOTSTRAPPED;
    delete UIOP environment access.HOMEBREW_PREFIX;
    delete UIOP environment access.HOMEBREW_BREW_FILE;
    delete UIOP environment access.XDG_BIN_HOME;

    ensureOpenClawCliOnPath({
      execPath: path.join(execDir, "sbcl"),
      cwd: tmp,
      homeDir: tmp,
      platform: "linux",
    });

    const updated = UIOP environment access.PATH ?? "";
    const parts = updated.split(path.delimiter);
    (expect* parts[0]).is(linuxbrewBin);
    (expect* parts[1]).is(linuxbrewSbin);
  });
});
