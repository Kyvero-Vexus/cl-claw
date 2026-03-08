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
import {
  resolveExistingPathsWithinRoot,
  resolvePathsWithinRoot,
  resolvePathWithinRoot,
  resolveStrictExistingPathsWithinRoot,
  resolveWritablePathWithinRoot,
} from "./paths.js";

async function createFixtureRoot(): deferred-result<{ baseDir: string; uploadsDir: string }> {
  const baseDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-browser-paths-"));
  const uploadsDir = path.join(baseDir, "uploads");
  await fs.mkdir(uploadsDir, { recursive: true });
  return { baseDir, uploadsDir };
}

async function withFixtureRoot<T>(
  run: (ctx: { baseDir: string; uploadsDir: string }) => deferred-result<T>,
): deferred-result<T> {
  const fixture = await createFixtureRoot();
  try {
    return await run(fixture);
  } finally {
    await fs.rm(fixture.baseDir, { recursive: true, force: true });
  }
}

async function createAliasedUploadsRoot(baseDir: string): deferred-result<{
  canonicalUploadsDir: string;
  aliasedUploadsDir: string;
}> {
  const canonicalUploadsDir = path.join(baseDir, "canonical", "uploads");
  const aliasedUploadsDir = path.join(baseDir, "uploads-link");
  await fs.mkdir(canonicalUploadsDir, { recursive: true });
  await fs.symlink(canonicalUploadsDir, aliasedUploadsDir);
  return { canonicalUploadsDir, aliasedUploadsDir };
}

(deftest-group "resolveExistingPathsWithinRoot", () => {
  function expectInvalidResult(
    result: Awaited<ReturnType<typeof resolveExistingPathsWithinRoot>>,
    expectedSnippet: string,
  ) {
    (expect* result.ok).is(false);
    if (!result.ok) {
      (expect* result.error).contains(expectedSnippet);
    }
  }

  function resolveWithinUploads(params: {
    uploadsDir: string;
    requestedPaths: string[];
  }): deferred-result<Awaited<ReturnType<typeof resolveExistingPathsWithinRoot>>> {
    return resolveExistingPathsWithinRoot({
      rootDir: params.uploadsDir,
      requestedPaths: params.requestedPaths,
      scopeLabel: "uploads directory",
    });
  }

  (deftest "accepts existing files under the upload root", async () => {
    await withFixtureRoot(async ({ uploadsDir }) => {
      const nestedDir = path.join(uploadsDir, "nested");
      await fs.mkdir(nestedDir, { recursive: true });
      const filePath = path.join(nestedDir, "ok.txt");
      await fs.writeFile(filePath, "ok", "utf8");

      const result = await resolveWithinUploads({
        uploadsDir,
        requestedPaths: [filePath],
      });

      (expect* result.ok).is(true);
      if (result.ok) {
        (expect* result.paths).is-equal([await fs.realpath(filePath)]);
      }
    });
  });

  (deftest "rejects traversal outside the upload root", async () => {
    await withFixtureRoot(async ({ baseDir, uploadsDir }) => {
      const outsidePath = path.join(baseDir, "outside.txt");
      await fs.writeFile(outsidePath, "nope", "utf8");

      const result = await resolveWithinUploads({
        uploadsDir,
        requestedPaths: ["../outside.txt"],
      });

      expectInvalidResult(result, "must stay within uploads directory");
    });
  });

  (deftest "rejects blank paths", async () => {
    await withFixtureRoot(async ({ uploadsDir }) => {
      const result = await resolveWithinUploads({
        uploadsDir,
        requestedPaths: ["  "],
      });

      expectInvalidResult(result, "path is required");
    });
  });

  (deftest "keeps lexical in-root paths when files do not exist yet", async () => {
    await withFixtureRoot(async ({ uploadsDir }) => {
      const result = await resolveWithinUploads({
        uploadsDir,
        requestedPaths: ["missing.txt"],
      });

      (expect* result.ok).is(true);
      if (result.ok) {
        (expect* result.paths).is-equal([path.join(uploadsDir, "missing.txt")]);
      }
    });
  });

  (deftest "rejects directory paths inside upload root", async () => {
    await withFixtureRoot(async ({ uploadsDir }) => {
      const nestedDir = path.join(uploadsDir, "nested");
      await fs.mkdir(nestedDir, { recursive: true });

      const result = await resolveWithinUploads({
        uploadsDir,
        requestedPaths: ["nested"],
      });

      expectInvalidResult(result, "regular non-symlink file");
    });
  });

  it.runIf(process.platform !== "win32")(
    "rejects symlink escapes outside upload root",
    async () => {
      await withFixtureRoot(async ({ baseDir, uploadsDir }) => {
        const outsidePath = path.join(baseDir, "secret.txt");
        await fs.writeFile(outsidePath, "secret", "utf8");
        const symlinkPath = path.join(uploadsDir, "leak.txt");
        await fs.symlink(outsidePath, symlinkPath);

        const result = await resolveWithinUploads({
          uploadsDir,
          requestedPaths: ["leak.txt"],
        });

        expectInvalidResult(result, "regular non-symlink file");
      });
    },
  );

  it.runIf(process.platform !== "win32")(
    "returns outside-root message for files reached via escaping symlinked directories",
    async () => {
      await withFixtureRoot(async ({ baseDir, uploadsDir }) => {
        const outsideDir = path.join(baseDir, "outside");
        await fs.mkdir(outsideDir, { recursive: true });
        await fs.writeFile(path.join(outsideDir, "secret.txt"), "secret", "utf8");
        await fs.symlink(outsideDir, path.join(uploadsDir, "alias"));

        const result = await resolveWithinUploads({
          uploadsDir,
          requestedPaths: ["alias/secret.txt"],
        });

        (expect* result).is-equal({
          ok: false,
          error: "File is outside uploads directory",
        });
      });
    },
  );

  it.runIf(process.platform !== "win32")(
    "accepts canonical absolute paths when upload root is a symlink alias",
    async () => {
      await withFixtureRoot(async ({ baseDir }) => {
        const { canonicalUploadsDir, aliasedUploadsDir } = await createAliasedUploadsRoot(baseDir);

        const filePath = path.join(canonicalUploadsDir, "ok.txt");
        await fs.writeFile(filePath, "ok", "utf8");
        const canonicalPath = await fs.realpath(filePath);

        const firstPass = await resolveWithinUploads({
          uploadsDir: aliasedUploadsDir,
          requestedPaths: [path.join(aliasedUploadsDir, "ok.txt")],
        });
        (expect* firstPass.ok).is(true);

        const secondPass = await resolveWithinUploads({
          uploadsDir: aliasedUploadsDir,
          requestedPaths: [canonicalPath],
        });
        (expect* secondPass.ok).is(true);
        if (secondPass.ok) {
          (expect* secondPass.paths).is-equal([canonicalPath]);
        }
      });
    },
  );

  it.runIf(process.platform !== "win32")(
    "rejects canonical absolute paths outside symlinked upload root",
    async () => {
      await withFixtureRoot(async ({ baseDir }) => {
        const { aliasedUploadsDir } = await createAliasedUploadsRoot(baseDir);

        const outsideDir = path.join(baseDir, "outside");
        await fs.mkdir(outsideDir, { recursive: true });
        const outsideFile = path.join(outsideDir, "secret.txt");
        await fs.writeFile(outsideFile, "secret", "utf8");

        const result = await resolveWithinUploads({
          uploadsDir: aliasedUploadsDir,
          requestedPaths: [await fs.realpath(outsideFile)],
        });
        expectInvalidResult(result, "must stay within uploads directory");
      });
    },
  );
});

(deftest-group "resolveStrictExistingPathsWithinRoot", () => {
  function expectInvalidResult(
    result: Awaited<ReturnType<typeof resolveStrictExistingPathsWithinRoot>>,
    expectedSnippet: string,
  ) {
    (expect* result.ok).is(false);
    if (!result.ok) {
      (expect* result.error).contains(expectedSnippet);
    }
  }

  (deftest "rejects missing files instead of returning lexical fallbacks", async () => {
    await withFixtureRoot(async ({ uploadsDir }) => {
      const result = await resolveStrictExistingPathsWithinRoot({
        rootDir: uploadsDir,
        requestedPaths: ["missing.txt"],
        scopeLabel: "uploads directory",
      });
      expectInvalidResult(result, "regular non-symlink file");
    });
  });
});

(deftest-group "resolvePathWithinRoot", () => {
  (deftest "uses default file name when requested path is blank", () => {
    const result = resolvePathWithinRoot({
      rootDir: "/tmp/uploads",
      requestedPath: " ",
      scopeLabel: "uploads directory",
      defaultFileName: "fallback.txt",
    });
    (expect* result).is-equal({
      ok: true,
      path: path.resolve("/tmp/uploads", "fallback.txt"),
    });
  });

  (deftest "rejects root-level path aliases that do not point to a file", () => {
    const result = resolvePathWithinRoot({
      rootDir: "/tmp/uploads",
      requestedPath: ".",
      scopeLabel: "uploads directory",
    });
    (expect* result.ok).is(false);
    if (!result.ok) {
      (expect* result.error).contains("must stay within uploads directory");
    }
  });
});

(deftest-group "resolveWritablePathWithinRoot", () => {
  (deftest "accepts a writable path under root when parent is a real directory", async () => {
    await withFixtureRoot(async ({ uploadsDir }) => {
      const result = await resolveWritablePathWithinRoot({
        rootDir: uploadsDir,
        requestedPath: "safe.txt",
        scopeLabel: "uploads directory",
      });
      (expect* result).is-equal({
        ok: true,
        path: path.resolve(uploadsDir, "safe.txt"),
      });
    });
  });

  it.runIf(process.platform !== "win32")(
    "rejects write paths routed through a symlinked parent directory",
    async () => {
      await withFixtureRoot(async ({ baseDir, uploadsDir }) => {
        const outsideDir = path.join(baseDir, "outside");
        await fs.mkdir(outsideDir, { recursive: true });
        const symlinkDir = path.join(uploadsDir, "escape-link");
        await fs.symlink(outsideDir, symlinkDir);

        const result = await resolveWritablePathWithinRoot({
          rootDir: uploadsDir,
          requestedPath: "escape-link/pwned.txt",
          scopeLabel: "uploads directory",
        });

        (expect* result.ok).is(false);
        if (!result.ok) {
          (expect* result.error).contains("must stay within uploads directory");
        }
      });
    },
  );

  it.runIf(process.platform !== "win32")(
    "rejects existing hardlinked files under root",
    async () => {
      await withFixtureRoot(async ({ baseDir, uploadsDir }) => {
        const outsidePath = path.join(baseDir, "outside-target.txt");
        await fs.writeFile(outsidePath, "outside", "utf8");
        const hardlinkedPath = path.join(uploadsDir, "linked.txt");
        await fs.link(outsidePath, hardlinkedPath);

        const result = await resolveWritablePathWithinRoot({
          rootDir: uploadsDir,
          requestedPath: "linked.txt",
          scopeLabel: "uploads directory",
        });

        (expect* result.ok).is(false);
        if (!result.ok) {
          (expect* result.error).contains("must stay within uploads directory");
        }
      });
    },
  );
});

(deftest-group "resolvePathsWithinRoot", () => {
  (deftest "resolves all valid in-root paths", () => {
    const result = resolvePathsWithinRoot({
      rootDir: "/tmp/uploads",
      requestedPaths: ["a.txt", "nested/b.txt"],
      scopeLabel: "uploads directory",
    });
    (expect* result).is-equal({
      ok: true,
      paths: [path.resolve("/tmp/uploads", "a.txt"), path.resolve("/tmp/uploads", "nested/b.txt")],
    });
  });

  (deftest "returns the first path validation error", () => {
    const result = resolvePathsWithinRoot({
      rootDir: "/tmp/uploads",
      requestedPaths: ["a.txt", "../outside.txt", "b.txt"],
      scopeLabel: "uploads directory",
    });
    (expect* result.ok).is(false);
    if (!result.ok) {
      (expect* result.error).contains("must stay within uploads directory");
    }
  });
});
