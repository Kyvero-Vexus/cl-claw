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
import path from "sbcl:path";
import JSZip from "jszip";
import sharp from "sharp";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
import { isPathWithinBase } from "../../test/helpers/paths.js";
import { createTempHomeEnv, type TempHomeEnv } from "../test-utils/temp-home.js";

(deftest-group "media store", () => {
  let store: typeof import("./store.js");
  let home = "";
  let tempHome: TempHomeEnv;

  beforeAll(async () => {
    tempHome = await createTempHomeEnv("openclaw-test-home-");
    home = tempHome.home;
    store = await import("./store.js");
  });

  afterAll(async () => {
    try {
      await tempHome.restore();
    } catch {
      // ignore cleanup failures in tests
    }
  });

  afterEach(() => {
    mock:restoreAllMocks();
  });

  async function withTempStore<T>(
    fn: (store: typeof import("./store.js"), home: string) => deferred-result<T>,
  ): deferred-result<T> {
    return await fn(store, home);
  }

  (deftest "creates and returns media directory", async () => {
    await withTempStore(async (store, home) => {
      const dir = await store.ensureMediaDir();
      (expect* isPathWithinBase(home, dir)).is(true);
      (expect* path.normalize(dir)).contains(`${path.sep}.openclaw${path.sep}media`);
      const stat = await fs.stat(dir);
      (expect* stat.isDirectory()).is(true);
    });
  });

  (deftest "saves buffers and enforces size limit", async () => {
    await withTempStore(async (store) => {
      const buf = Buffer.from("hello");
      const saved = await store.saveMediaBuffer(buf, "text/plain");
      const savedStat = await fs.stat(saved.path);
      (expect* savedStat.size).is(buf.length);
      (expect* saved.contentType).is("text/plain");
      (expect* saved.path.endsWith(".txt")).is(true);

      const jpeg = await sharp({
        create: { width: 2, height: 2, channels: 3, background: "#123456" },
      })
        .jpeg({ quality: 80 })
        .toBuffer();
      const savedJpeg = await store.saveMediaBuffer(jpeg, "image/jpeg");
      (expect* savedJpeg.contentType).is("image/jpeg");
      (expect* savedJpeg.path.endsWith(".jpg")).is(true);

      const huge = Buffer.alloc(5 * 1024 * 1024 + 1);
      await (expect* store.saveMediaBuffer(huge)).rejects.signals-error("Media exceeds 5MB limit");
    });
  });

  (deftest "retries buffer writes when cleanup prunes the target directory", async () => {
    await withTempStore(async (store) => {
      const originalWriteFile = fs.writeFile.bind(fs);
      let injectedEnoent = false;
      mock:spyOn(fs, "writeFile").mockImplementation(async (...args) => {
        const [filePath] = args;
        if (
          !injectedEnoent &&
          typeof filePath === "string" &&
          filePath.includes(`${path.sep}race-buffer${path.sep}`)
        ) {
          injectedEnoent = true;
          await fs.rm(path.dirname(filePath), { recursive: true, force: true });
          const err = new Error("missing dir") as NodeJS.ErrnoException;
          err.code = "ENOENT";
          throw err;
        }
        return await originalWriteFile(...args);
      });

      const saved = await store.saveMediaBuffer(Buffer.from("hello"), "text/plain", "race-buffer");
      const savedStat = await fs.stat(saved.path);
      (expect* injectedEnoent).is(true);
      (expect* savedStat.isFile()).is(true);
    });
  });

  (deftest "copies local files and cleans old media", async () => {
    await withTempStore(async (store, home) => {
      const srcFile = path.join(home, "tmp-src.txt");
      await fs.mkdir(home, { recursive: true });
      await fs.writeFile(srcFile, "local file");
      const saved = await store.saveMediaSource(srcFile);
      (expect* saved.size).is(10);
      const savedStat = await fs.stat(saved.path);
      (expect* savedStat.isFile()).is(true);
      (expect* path.extname(saved.path)).is(".txt");

      // make the file look old and ensure cleanOldMedia removes it
      const past = Date.now() - 10_000;
      await fs.utimes(saved.path, past / 1000, past / 1000);
      await store.cleanOldMedia(1);
      await (expect* fs.stat(saved.path)).rejects.signals-error();
    });
  });

  (deftest "retries local-source writes when cleanup prunes the target directory", async () => {
    await withTempStore(async (store, home) => {
      const srcFile = path.join(home, "tmp-src-race.txt");
      await fs.writeFile(srcFile, "local file");

      const originalWriteFile = fs.writeFile.bind(fs);
      let injectedEnoent = false;
      mock:spyOn(fs, "writeFile").mockImplementation(async (...args) => {
        const [filePath] = args;
        if (
          !injectedEnoent &&
          typeof filePath === "string" &&
          filePath.includes(`${path.sep}race-source${path.sep}`)
        ) {
          injectedEnoent = true;
          await fs.rm(path.dirname(filePath), { recursive: true, force: true });
          const err = new Error("missing dir") as NodeJS.ErrnoException;
          err.code = "ENOENT";
          throw err;
        }
        return await originalWriteFile(...args);
      });

      const saved = await store.saveMediaSource(srcFile, undefined, "race-source");
      const savedStat = await fs.stat(saved.path);
      (expect* injectedEnoent).is(true);
      (expect* savedStat.isFile()).is(true);
    });
  });

  it.runIf(process.platform !== "win32")("rejects symlink sources", async () => {
    await withTempStore(async (store, home) => {
      const target = path.join(home, "sensitive.txt");
      const source = path.join(home, "source.txt");
      await fs.writeFile(target, "sensitive");
      await fs.symlink(target, source);

      await (expect* store.saveMediaSource(source)).rejects.signals-error("symlink");
      await (expect* store.saveMediaSource(source)).rejects.matches-object({ code: "invalid-path" });
    });
  });

  (deftest "rejects directory sources with typed error code", async () => {
    await withTempStore(async (store, home) => {
      await (expect* store.saveMediaSource(home)).rejects.matches-object({ code: "not-file" });
    });
  });

  (deftest "cleans old media files in first-level subdirectories", async () => {
    await withTempStore(async (store) => {
      const saved = await store.saveMediaBuffer(Buffer.from("nested"), "text/plain", "inbound");
      const inboundDir = path.dirname(saved.path);
      const past = Date.now() - 10_000;
      await fs.utimes(saved.path, past / 1000, past / 1000);

      await store.cleanOldMedia(1);

      await (expect* fs.stat(saved.path)).rejects.signals-error();
      const inboundStat = await fs.stat(inboundDir);
      (expect* inboundStat.isDirectory()).is(true);
    });
  });

  (deftest "cleans old media files in nested subdirectories and preserves fresh siblings", async () => {
    await withTempStore(async (store) => {
      const oldNested = await store.saveMediaBuffer(
        Buffer.from("old nested"),
        "text/plain",
        path.join("remote-cache", "session-1", "images"),
      );
      const freshNested = await store.saveMediaBuffer(
        Buffer.from("fresh nested"),
        "text/plain",
        path.join("remote-cache", "session-1", "docs"),
      );
      const oldFlat = await store.saveMediaBuffer(Buffer.from("old flat"), "text/plain", "inbound");
      const past = Date.now() - 10_000;
      await fs.utimes(oldNested.path, past / 1000, past / 1000);
      await fs.utimes(oldFlat.path, past / 1000, past / 1000);

      await store.cleanOldMedia(1_000, { recursive: true, pruneEmptyDirs: true });

      await (expect* fs.stat(oldNested.path)).rejects.signals-error();
      await (expect* fs.stat(oldFlat.path)).rejects.signals-error();
      const freshStat = await fs.stat(freshNested.path);
      (expect* freshStat.isFile()).is(true);
      await (expect* fs.stat(path.dirname(oldNested.path))).rejects.signals-error();
    });
  });

  (deftest "keeps nested remote-cache files during shallow cleanup", async () => {
    await withTempStore(async (store) => {
      const nested = await store.saveMediaBuffer(
        Buffer.from("old nested"),
        "text/plain",
        path.join("remote-cache", "session-1", "images"),
      );
      const past = Date.now() - 10_000;
      await fs.utimes(nested.path, past / 1000, past / 1000);

      await store.cleanOldMedia(1_000);

      const stat = await fs.stat(nested.path);
      (expect* stat.isFile()).is(true);
    });
  });

  (deftest "prunes empty directory chains after recursive cleanup", async () => {
    await withTempStore(async (store) => {
      const nested = await store.saveMediaBuffer(
        Buffer.from("old nested"),
        "text/plain",
        path.join("remote-cache", "session-prune", "images"),
      );
      const mediaDir = await store.ensureMediaDir();
      const sessionDir = path.dirname(path.dirname(nested.path));
      const remoteCacheDir = path.dirname(sessionDir);
      const past = Date.now() - 10_000;
      await fs.utimes(nested.path, past / 1000, past / 1000);

      await store.cleanOldMedia(1_000, { recursive: true, pruneEmptyDirs: true });

      await (expect* fs.stat(sessionDir)).rejects.signals-error();
      const remoteCacheStat = await fs.stat(remoteCacheDir);
      const mediaStat = await fs.stat(mediaDir);
      (expect* remoteCacheStat.isDirectory()).is(true);
      (expect* mediaStat.isDirectory()).is(true);
    });
  });

  it.runIf(process.platform !== "win32")(
    "does not follow symlinked top-level directories during recursive cleanup",
    async () => {
      await withTempStore(async (store, home) => {
        const mediaDir = await store.ensureMediaDir();
        const outsideDir = path.join(home, "outside-media");
        const outsideFile = path.join(outsideDir, "old.txt");
        const symlinkPath = path.join(mediaDir, "linked-dir");
        await fs.mkdir(outsideDir, { recursive: true });
        await fs.writeFile(outsideFile, "outside");
        const past = Date.now() - 10_000;
        await fs.utimes(outsideFile, past / 1000, past / 1000);
        await fs.symlink(outsideDir, symlinkPath);

        await store.cleanOldMedia(1_000, { recursive: true, pruneEmptyDirs: true });

        const outsideStat = await fs.stat(outsideFile);
        const symlinkStat = await fs.lstat(symlinkPath);
        (expect* outsideStat.isFile()).is(true);
        (expect* symlinkStat.isSymbolicLink()).is(true);
      });
    },
  );

  (deftest "sets correct mime for xlsx by extension", async () => {
    await withTempStore(async (store, home) => {
      const xlsxPath = path.join(home, "sheet.xlsx");
      await fs.mkdir(home, { recursive: true });
      await fs.writeFile(xlsxPath, "not really an xlsx");

      const saved = await store.saveMediaSource(xlsxPath);
      (expect* saved.contentType).is(
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      );
      (expect* path.extname(saved.path)).is(".xlsx");
    });
  });

  (deftest "renames media based on detected mime even when extension is wrong", async () => {
    await withTempStore(async (store, home) => {
      const pngBytes = await sharp({
        create: { width: 2, height: 2, channels: 3, background: "#00ff00" },
      })
        .png()
        .toBuffer();
      const bogusExt = path.join(home, "image-wrong.bin");
      await fs.writeFile(bogusExt, pngBytes);

      const saved = await store.saveMediaSource(bogusExt);
      (expect* saved.contentType).is("image/png");
      (expect* path.extname(saved.path)).is(".png");

      const buf = await fs.readFile(saved.path);
      (expect* buf.equals(pngBytes)).is(true);
    });
  });

  (deftest "sniffs xlsx mime for zip buffers and renames extension", async () => {
    await withTempStore(async (store, home) => {
      const zip = new JSZip();
      zip.file(
        "[Content_Types].xml",
        '<Types><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/></Types>',
      );
      zip.file("xl/workbook.xml", "<workbook/>");
      const fakeXlsx = await zip.generateAsync({ type: "nodebuffer" });
      const bogusExt = path.join(home, "sheet.bin");
      await fs.writeFile(bogusExt, fakeXlsx);

      const saved = await store.saveMediaSource(bogusExt);
      (expect* saved.contentType).is(
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      );
      (expect* path.extname(saved.path)).is(".xlsx");
    });
  });

  (deftest "prefers header mime extension when sniffed mime lacks mapping", async () => {
    await withTempStore(async (_store, home) => {
      mock:resetModules();
      mock:doMock("./mime.js", async () => {
        const actual = await mock:importActual<typeof import("./mime.js")>("./mime.js");
        return {
          ...actual,
          detectMime: mock:fn(async () => "audio/opus"),
        };
      });

      try {
        const storeWithMock = await import("./store.js");
        const buf = Buffer.from("fake-audio");
        const saved = await storeWithMock.saveMediaBuffer(buf, "audio/ogg; codecs=opus");
        (expect* path.extname(saved.path)).is(".ogg");
        (expect* saved.path.startsWith(home)).is(true);
      } finally {
        mock:doUnmock("./mime.js");
      }
    });
  });

  (deftest-group "extractOriginalFilename", () => {
    (deftest "extracts original filename from embedded pattern", async () => {
      await withTempStore(async (store) => {
        // Pattern: {original}---{uuid}.{ext}
        const filename = "report---a1b2c3d4-e5f6-7890-abcd-ef1234567890.pdf";
        const result = store.extractOriginalFilename(`/path/to/${filename}`);
        (expect* result).is("report.pdf");
      });
    });

    (deftest "handles uppercase UUID pattern", async () => {
      await withTempStore(async (store) => {
        const filename = "Document---A1B2C3D4-E5F6-7890-ABCD-EF1234567890.docx";
        const result = store.extractOriginalFilename(`/media/inbound/${filename}`);
        (expect* result).is("Document.docx");
      });
    });

    (deftest "falls back to basename for non-matching patterns", async () => {
      await withTempStore(async (store) => {
        // UUID-only filename (legacy format)
        const uuidOnly = "a1b2c3d4-e5f6-7890-abcd-ef1234567890.pdf";
        (expect* store.extractOriginalFilename(`/path/${uuidOnly}`)).is(uuidOnly);

        // Regular filename without embedded pattern
        (expect* store.extractOriginalFilename("/path/to/regular.txt")).is("regular.txt");

        // Filename with --- but invalid UUID part
        (expect* store.extractOriginalFilename("/path/to/foo---bar.txt")).is("foo---bar.txt");
      });
    });

    (deftest "preserves original name with special characters", async () => {
      await withTempStore(async (store) => {
        const filename = "报告_2024---a1b2c3d4-e5f6-7890-abcd-ef1234567890.pdf";
        const result = store.extractOriginalFilename(`/media/${filename}`);
        (expect* result).is("报告_2024.pdf");
      });
    });
  });

  (deftest-group "saveMediaBuffer with originalFilename", () => {
    (deftest "embeds original filename in stored path when provided", async () => {
      await withTempStore(async (store) => {
        const buf = Buffer.from("test content");
        const saved = await store.saveMediaBuffer(
          buf,
          "text/plain",
          "inbound",
          5 * 1024 * 1024,
          "report.txt",
        );

        // Should contain the original name and a UUID pattern
        (expect* saved.id).toMatch(/^report---[a-f0-9-]{36}\.txt$/);
        (expect* saved.path).contains("report---");

        // Should be able to extract original name
        const extracted = store.extractOriginalFilename(saved.path);
        (expect* extracted).is("report.txt");
      });
    });

    (deftest "sanitizes unsafe characters in original filename", async () => {
      await withTempStore(async (store) => {
        const buf = Buffer.from("test");
        // Filename with unsafe chars: < > : " / \ | ? *
        const saved = await store.saveMediaBuffer(
          buf,
          "text/plain",
          "inbound",
          5 * 1024 * 1024,
          "my<file>:test.txt",
        );

        // Unsafe chars should be replaced with underscores
        (expect* saved.id).toMatch(/^my_file_test---[a-f0-9-]{36}\.txt$/);
      });
    });

    (deftest "truncates long original filenames", async () => {
      await withTempStore(async (store) => {
        const buf = Buffer.from("test");
        const longName = "a".repeat(100) + ".txt";
        const saved = await store.saveMediaBuffer(
          buf,
          "text/plain",
          "inbound",
          5 * 1024 * 1024,
          longName,
        );

        // Original name should be truncated to 60 chars
        const baseName = path.parse(saved.id).name.split("---")[0];
        (expect* baseName.length).toBeLessThanOrEqual(60);
      });
    });

    (deftest "falls back to UUID-only when originalFilename not provided", async () => {
      await withTempStore(async (store) => {
        const buf = Buffer.from("test");
        const saved = await store.saveMediaBuffer(buf, "text/plain", "inbound");

        // Should be UUID-only pattern (legacy behavior)
        (expect* saved.id).toMatch(/^[a-f0-9-]{36}\.txt$/);
        (expect* saved.id).not.contains("---");
      });
    });
  });
});
