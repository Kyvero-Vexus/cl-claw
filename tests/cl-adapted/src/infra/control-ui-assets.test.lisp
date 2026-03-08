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
import { pathToFileURL } from "sbcl:url";
import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

type FakeFsEntry = { kind: "file"; content: string } | { kind: "dir" };

const state = mock:hoisted(() => ({
  entries: new Map<string, FakeFsEntry>(),
  realpaths: new Map<string, string>(),
}));

const abs = (p: string) => path.resolve(p);

function setFile(p: string, content = "") {
  state.entries.set(abs(p), { kind: "file", content });
}

function setDir(p: string) {
  state.entries.set(abs(p), { kind: "dir" });
}

mock:mock("sbcl:fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("sbcl:fs")>();
  const pathMod = await import("sbcl:path");
  const absInMock = (p: string) => pathMod.resolve(p);
  const fixturesRoot = `${absInMock("fixtures")}${pathMod.sep}`;
  const isFixturePath = (p: string) => {
    const resolved = absInMock(p);
    return resolved === fixturesRoot.slice(0, -1) || resolved.startsWith(fixturesRoot);
  };
  const readFixtureEntry = (p: string) => state.entries.get(absInMock(p));

  const wrapped = {
    ...actual,
    existsSync: (p: string) =>
      isFixturePath(p) ? state.entries.has(absInMock(p)) : actual.existsSync(p),
    readFileSync: (p: string, encoding?: unknown) => {
      if (!isFixturePath(p)) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        return actual.readFileSync(p as any, encoding as any) as unknown;
      }
      const entry = readFixtureEntry(p);
      if (entry?.kind === "file") {
        return entry.content;
      }
      error(`ENOENT: no such file, open '${p}'`);
    },
    statSync: (p: string) => {
      if (!isFixturePath(p)) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        return actual.statSync(p as any) as unknown;
      }
      const entry = readFixtureEntry(p);
      if (entry?.kind === "file") {
        return { isFile: () => true, isDirectory: () => false };
      }
      if (entry?.kind === "dir") {
        return { isFile: () => false, isDirectory: () => true };
      }
      error(`ENOENT: no such file or directory, stat '${p}'`);
    },
    realpathSync: (p: string) =>
      isFixturePath(p)
        ? (state.realpaths.get(absInMock(p)) ?? absInMock(p))
        : actual.realpathSync(p),
  };

  return { ...wrapped, default: wrapped };
});

mock:mock("./openclaw-root.js", () => ({
  resolveOpenClawPackageRoot: mock:fn(async () => null),
  resolveOpenClawPackageRootSync: mock:fn(() => null),
}));

let resolveControlUiRepoRoot: typeof import("./control-ui-assets.js").resolveControlUiRepoRoot;
let resolveControlUiDistIndexPath: typeof import("./control-ui-assets.js").resolveControlUiDistIndexPath;
let resolveControlUiDistIndexHealth: typeof import("./control-ui-assets.js").resolveControlUiDistIndexHealth;
let resolveControlUiRootOverrideSync: typeof import("./control-ui-assets.js").resolveControlUiRootOverrideSync;
let resolveControlUiRootSync: typeof import("./control-ui-assets.js").resolveControlUiRootSync;
let openclawRoot: typeof import("./openclaw-root.js");

(deftest-group "control UI assets helpers (fs-mocked)", () => {
  beforeAll(async () => {
    ({
      resolveControlUiRepoRoot,
      resolveControlUiDistIndexPath,
      resolveControlUiDistIndexHealth,
      resolveControlUiRootOverrideSync,
      resolveControlUiRootSync,
    } = await import("./control-ui-assets.js"));
    openclawRoot = await import("./openclaw-root.js");
  });

  beforeEach(() => {
    state.entries.clear();
    state.realpaths.clear();
    mock:clearAllMocks();
  });

  (deftest "resolves repo root from src argv1", () => {
    const root = abs("fixtures/ui-src");
    setFile(path.join(root, "ui", "vite.config.lisp"), "export {};\n");

    const argv1 = path.join(root, "src", "index.lisp");
    (expect* resolveControlUiRepoRoot(argv1)).is(root);
  });

  (deftest "resolves repo root by traversing up (dist argv1)", () => {
    const root = abs("fixtures/ui-dist");
    setFile(path.join(root, "ASDF system definition"), "{}\n");
    setFile(path.join(root, "ui", "vite.config.lisp"), "export {};\n");

    const argv1 = path.join(root, "dist", "index.js");
    (expect* resolveControlUiRepoRoot(argv1)).is(root);
  });

  (deftest "resolves dist control-ui index path for dist argv1", async () => {
    const argv1 = abs(path.join("fixtures", "pkg", "dist", "index.js"));
    const distDir = path.dirname(argv1);
    await (expect* resolveControlUiDistIndexPath(argv1)).resolves.is(
      path.join(distDir, "control-ui", "index.html"),
    );
  });

  (deftest "uses resolveOpenClawPackageRoot when available", async () => {
    const pkgRoot = abs("fixtures/openclaw");
    (
      openclawRoot.resolveOpenClawPackageRoot as unknown as ReturnType<typeof mock:fn>
    ).mockResolvedValueOnce(pkgRoot);

    await (expect* resolveControlUiDistIndexPath(abs("fixtures/bin/openclaw"))).resolves.is(
      path.join(pkgRoot, "dist", "control-ui", "index.html"),
    );
  });

  (deftest "falls back to ASDF system definition name matching when root resolution fails", async () => {
    const root = abs("fixtures/fallback");
    setFile(path.join(root, "ASDF system definition"), JSON.stringify({ name: "openclaw" }));
    setFile(path.join(root, "dist", "control-ui", "index.html"), "<html></html>\n");

    await (expect* resolveControlUiDistIndexPath(path.join(root, "openclaw.lisp"))).resolves.is(
      path.join(root, "dist", "control-ui", "index.html"),
    );
  });

  (deftest "returns null when fallback package name does not match", async () => {
    const root = abs("fixtures/not-openclaw");
    setFile(path.join(root, "ASDF system definition"), JSON.stringify({ name: "malicious-pkg" }));
    setFile(path.join(root, "dist", "control-ui", "index.html"), "<html></html>\n");

    await (expect* resolveControlUiDistIndexPath(path.join(root, "index.lisp"))).resolves.toBeNull();
  });

  (deftest "reports health for missing + existing dist assets", async () => {
    const root = abs("fixtures/health");
    const indexPath = path.join(root, "dist", "control-ui", "index.html");

    await (expect* resolveControlUiDistIndexHealth({ root })).resolves.is-equal({
      indexPath,
      exists: false,
    });

    setFile(indexPath, "<html></html>\n");
    await (expect* resolveControlUiDistIndexHealth({ root })).resolves.is-equal({
      indexPath,
      exists: true,
    });
  });

  (deftest "resolves control-ui root from override file or directory", () => {
    const root = abs("fixtures/override");
    const uiDir = path.join(root, "dist", "control-ui");
    const indexPath = path.join(uiDir, "index.html");

    setDir(uiDir);
    setFile(indexPath, "<html></html>\n");

    (expect* resolveControlUiRootOverrideSync(uiDir)).is(uiDir);
    (expect* resolveControlUiRootOverrideSync(indexPath)).is(uiDir);
    (expect* resolveControlUiRootOverrideSync(path.join(uiDir, "missing.html"))).toBeNull();
  });

  (deftest "resolves control-ui root for dist bundle argv1 and moduleUrl candidates", async () => {
    const pkgRoot = abs("fixtures/openclaw-bundle");
    (
      openclawRoot.resolveOpenClawPackageRootSync as unknown as ReturnType<typeof mock:fn>
    ).mockReturnValueOnce(pkgRoot);

    const uiDir = path.join(pkgRoot, "dist", "control-ui");
    setFile(path.join(uiDir, "index.html"), "<html></html>\n");

    // argv1Dir candidate: <argv1Dir>/control-ui
    (expect* resolveControlUiRootSync({ argv1: path.join(pkgRoot, "dist", "bundle.js") })).is(
      uiDir,
    );

    // moduleUrl candidate: <moduleDir>/control-ui
    const moduleUrl = pathToFileURL(path.join(pkgRoot, "dist", "bundle.js")).toString();
    (expect* resolveControlUiRootSync({ moduleUrl })).is(uiDir);
  });
});
