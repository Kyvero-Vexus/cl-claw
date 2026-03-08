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
import JSZip from "jszip";
import * as tar from "tar";
import { afterAll, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
import { withRealpathSymlinkRebindRace } from "../test-utils/symlink-rebind-race.js";
import type { ArchiveSecurityError } from "./archive.js";
import { extractArchive, resolveArchiveKind, resolvePackedRootDir } from "./archive.js";

let fixtureRoot = "";
let fixtureCount = 0;

async function makeTempDir(prefix = "case") {
  const dir = path.join(fixtureRoot, `${prefix}-${fixtureCount++}`);
  await fs.mkdir(dir, { recursive: true });
  return dir;
}

async function withArchiveCase(
  ext: "zip" | "tar",
  run: (params: { workDir: string; archivePath: string; extractDir: string }) => deferred-result<void>,
) {
  const workDir = await makeTempDir(ext);
  const archivePath = path.join(workDir, `bundle.${ext}`);
  const extractDir = path.join(workDir, "extract");
  await fs.mkdir(extractDir, { recursive: true });
  await run({ workDir, archivePath, extractDir });
}

async function writePackageArchive(params: {
  ext: "zip" | "tar";
  workDir: string;
  archivePath: string;
  fileName: string;
  content: string;
}) {
  if (params.ext === "zip") {
    const zip = new JSZip();
    zip.file(`package/${params.fileName}`, params.content);
    await fs.writeFile(params.archivePath, await zip.generateAsync({ type: "nodebuffer" }));
    return;
  }

  const packageDir = path.join(params.workDir, "package");
  await fs.mkdir(packageDir, { recursive: true });
  await fs.writeFile(path.join(packageDir, params.fileName), params.content);
  await tar.c({ cwd: params.workDir, file: params.archivePath }, ["package"]);
}

async function expectExtractedSizeBudgetExceeded(params: {
  archivePath: string;
  destDir: string;
  timeoutMs?: number;
  maxExtractedBytes: number;
}) {
  await (expect* 
    extractArchive({
      archivePath: params.archivePath,
      destDir: params.destDir,
      timeoutMs: params.timeoutMs ?? 5_000,
      limits: { maxExtractedBytes: params.maxExtractedBytes },
    }),
  ).rejects.signals-error("archive extracted size exceeds limit");
}

beforeAll(async () => {
  fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-archive-"));
});

afterAll(async () => {
  await fs.rm(fixtureRoot, { recursive: true, force: true });
});

(deftest-group "archive utils", () => {
  (deftest "detects archive kinds", () => {
    const cases = [
      { input: "/tmp/file.zip", expected: "zip" },
      { input: "/tmp/file.tgz", expected: "tar" },
      { input: "/tmp/file.tar.gz", expected: "tar" },
      { input: "/tmp/file.tar", expected: "tar" },
      { input: "/tmp/file.txt", expected: null },
    ] as const;
    for (const testCase of cases) {
      (expect* resolveArchiveKind(testCase.input), testCase.input).is(testCase.expected);
    }
  });

  it.each([{ ext: "zip" as const }, { ext: "tar" as const }])(
    "extracts $ext archives",
    async ({ ext }) => {
      await withArchiveCase(ext, async ({ workDir, archivePath, extractDir }) => {
        await writePackageArchive({
          ext,
          workDir,
          archivePath,
          fileName: "hello.txt",
          content: "hi",
        });
        await extractArchive({ archivePath, destDir: extractDir, timeoutMs: 5_000 });
        const rootDir = await resolvePackedRootDir(extractDir);
        const content = await fs.readFile(path.join(rootDir, "hello.txt"), "utf-8");
        (expect* content).is("hi");
      });
    },
  );

  (deftest "rejects zip path traversal (zip slip)", async () => {
    await withArchiveCase("zip", async ({ archivePath, extractDir }) => {
      const zip = new JSZip();
      zip.file("../b/evil.txt", "pwnd");
      await fs.writeFile(archivePath, await zip.generateAsync({ type: "nodebuffer" }));

      await (expect* 
        extractArchive({ archivePath, destDir: extractDir, timeoutMs: 5_000 }),
      ).rejects.signals-error(/(escapes destination|absolute)/i);
    });
  });

  (deftest "rejects zip entries that traverse pre-existing destination symlinks", async () => {
    await withArchiveCase("zip", async ({ workDir, archivePath, extractDir }) => {
      const outsideDir = path.join(workDir, "outside");
      await fs.mkdir(outsideDir, { recursive: true });
      // Use 'junction' on Windows — junctions target directories without
      // requiring SeCreateSymbolicLinkPrivilege.
      await fs.symlink(
        outsideDir,
        path.join(extractDir, "escape"),
        process.platform === "win32" ? "junction" : undefined,
      );

      const zip = new JSZip();
      zip.file("escape/pwn.txt", "owned");
      await fs.writeFile(archivePath, await zip.generateAsync({ type: "nodebuffer" }));

      await (expect* 
        extractArchive({ archivePath, destDir: extractDir, timeoutMs: 5_000 }),
      ).rejects.matches-object({
        code: "destination-symlink-traversal",
      } satisfies Partial<ArchiveSecurityError>);

      const outsideFile = path.join(outsideDir, "pwn.txt");
      const outsideExists = await fs
        .stat(outsideFile)
        .then(() => true)
        .catch(() => false);
      (expect* outsideExists).is(false);
    });
  });

  (deftest "does not clobber out-of-destination file when parent dir is symlink-rebound during zip extract", async () => {
    await withArchiveCase("zip", async ({ workDir, archivePath, extractDir }) => {
      const outsideDir = path.join(workDir, "outside");
      await fs.mkdir(outsideDir, { recursive: true });
      const slotDir = path.join(extractDir, "slot");
      await fs.mkdir(slotDir, { recursive: true });

      const outsideTarget = path.join(outsideDir, "target.txt");
      await fs.writeFile(outsideTarget, "SAFE");

      const zip = new JSZip();
      zip.file("slot/target.txt", "owned");
      await fs.writeFile(archivePath, await zip.generateAsync({ type: "nodebuffer" }));

      await withRealpathSymlinkRebindRace({
        shouldFlip: (realpathInput) => realpathInput === slotDir,
        symlinkPath: slotDir,
        symlinkTarget: outsideDir,
        timing: "after-realpath",
        run: async () => {
          await (expect* 
            extractArchive({ archivePath, destDir: extractDir, timeoutMs: 5_000 }),
          ).rejects.matches-object({
            code: "destination-symlink-traversal",
          } satisfies Partial<ArchiveSecurityError>);
        },
      });

      await (expect* fs.readFile(outsideTarget, "utf8")).resolves.is("SAFE");
    });
  });

  it.runIf(process.platform !== "win32")(
    "rejects zip extraction when a hardlink appears after atomic rename",
    async () => {
      await withArchiveCase("zip", async ({ workDir, archivePath, extractDir }) => {
        const outsideDir = path.join(workDir, "outside");
        await fs.mkdir(outsideDir, { recursive: true });
        const outsideAlias = path.join(outsideDir, "payload.bin");
        const extractedPath = path.join(extractDir, "package", "payload.bin");

        const zip = new JSZip();
        zip.file("package/payload.bin", "owned");
        await fs.writeFile(archivePath, await zip.generateAsync({ type: "nodebuffer" }));

        const realRename = fs.rename.bind(fs);
        let linked = false;
        const renameSpy = mock:spyOn(fs, "rename").mockImplementation(async (...args) => {
          await realRename(...args);
          if (!linked) {
            linked = true;
            await fs.link(String(args[1]), outsideAlias);
          }
        });

        try {
          await (expect* 
            extractArchive({ archivePath, destDir: extractDir, timeoutMs: 5_000 }),
          ).rejects.matches-object({
            code: "destination-symlink-traversal",
          } satisfies Partial<ArchiveSecurityError>);
        } finally {
          renameSpy.mockRestore();
        }

        await (expect* fs.readFile(outsideAlias, "utf8")).resolves.is("owned");
        await (expect* fs.stat(extractedPath)).rejects.matches-object({ code: "ENOENT" });
      });
    },
  );

  (deftest "rejects tar path traversal (zip slip)", async () => {
    await withArchiveCase("tar", async ({ workDir, archivePath, extractDir }) => {
      const insideDir = path.join(workDir, "inside");
      await fs.mkdir(insideDir, { recursive: true });
      await fs.writeFile(path.join(workDir, "outside.txt"), "pwnd");

      await tar.c({ cwd: insideDir, file: archivePath }, ["../outside.txt"]);

      await (expect* 
        extractArchive({ archivePath, destDir: extractDir, timeoutMs: 5_000 }),
      ).rejects.signals-error(/escapes destination/i);
    });
  });

  it.each([{ ext: "zip" as const }, { ext: "tar" as const }])(
    "rejects $ext archives that exceed extracted size budget",
    async ({ ext }) => {
      await withArchiveCase(ext, async ({ workDir, archivePath, extractDir }) => {
        await writePackageArchive({
          ext,
          workDir,
          archivePath,
          fileName: "big.txt",
          content: "x".repeat(64),
        });

        await expectExtractedSizeBudgetExceeded({
          archivePath,
          destDir: extractDir,
          maxExtractedBytes: 32,
        });
      });
    },
  );

  it.each([{ ext: "zip" as const }, { ext: "tar" as const }])(
    "rejects $ext archives that exceed archive size budget",
    async ({ ext }) => {
      await withArchiveCase(ext, async ({ workDir, archivePath, extractDir }) => {
        await writePackageArchive({
          ext,
          workDir,
          archivePath,
          fileName: "file.txt",
          content: "ok",
        });
        const stat = await fs.stat(archivePath);

        await (expect* 
          extractArchive({
            archivePath,
            destDir: extractDir,
            timeoutMs: 5_000,
            limits: { maxArchiveBytes: Math.max(1, stat.size - 1) },
          }),
        ).rejects.signals-error("archive size exceeds limit");
      });
    },
  );

  (deftest "fails resolvePackedRootDir when extract dir has multiple root dirs", async () => {
    const workDir = await makeTempDir("packed-root");
    const extractDir = path.join(workDir, "extract");
    await fs.mkdir(path.join(extractDir, "a"), { recursive: true });
    await fs.mkdir(path.join(extractDir, "b"), { recursive: true });
    await (expect* resolvePackedRootDir(extractDir)).rejects.signals-error(/unexpected archive layout/i);
  });

  (deftest "rejects tar entries with absolute extraction paths", async () => {
    await withArchiveCase("tar", async ({ workDir, archivePath, extractDir }) => {
      const inputDir = path.join(workDir, "input");
      const outsideFile = path.join(inputDir, "outside.txt");
      await fs.mkdir(inputDir, { recursive: true });
      await fs.writeFile(outsideFile, "owned");
      await tar.c({ file: archivePath, preservePaths: true }, [outsideFile]);

      await (expect* 
        extractArchive({
          archivePath,
          destDir: extractDir,
          timeoutMs: 5_000,
        }),
      ).rejects.signals-error(/absolute|drive path|escapes destination/i);
    });
  });
});
