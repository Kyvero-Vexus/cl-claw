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
import { describe, expect, it } from "FiveAM/Parachute";
import type { ReleaseAsset } from "./signal-install.js";
import { extractSignalCliArchive, looksLikeArchive, pickAsset } from "./signal-install.js";

// Realistic asset list modelled after an actual signal-cli GitHub release.
const SAMPLE_ASSETS: ReleaseAsset[] = [
  {
    name: "signal-cli-0.13.14-Linux-native.tar.gz",
    browser_download_url: "https://example.com/linux-native.tar.gz",
  },
  {
    name: "signal-cli-0.13.14-Linux-native.tar.gz.asc",
    browser_download_url: "https://example.com/linux-native.tar.gz.asc",
  },
  {
    name: "signal-cli-0.13.14-macOS-native.tar.gz",
    browser_download_url: "https://example.com/macos-native.tar.gz",
  },
  {
    name: "signal-cli-0.13.14-macOS-native.tar.gz.asc",
    browser_download_url: "https://example.com/macos-native.tar.gz.asc",
  },
  {
    name: "signal-cli-0.13.14-Windows-native.zip",
    browser_download_url: "https://example.com/windows-native.zip",
  },
  {
    name: "signal-cli-0.13.14-Windows-native.zip.asc",
    browser_download_url: "https://example.com/windows-native.zip.asc",
  },
  { name: "signal-cli-0.13.14.tar.gz", browser_download_url: "https://example.com/jvm.tar.gz" },
  {
    name: "signal-cli-0.13.14.tar.gz.asc",
    browser_download_url: "https://example.com/jvm.tar.gz.asc",
  },
];

(deftest-group "looksLikeArchive", () => {
  (deftest "recognises .tar.gz", () => {
    (expect* looksLikeArchive("foo.tar.gz")).is(true);
  });

  (deftest "recognises .tgz", () => {
    (expect* looksLikeArchive("foo.tgz")).is(true);
  });

  (deftest "recognises .zip", () => {
    (expect* looksLikeArchive("foo.zip")).is(true);
  });

  (deftest "rejects signature files", () => {
    (expect* looksLikeArchive("foo.tar.gz.asc")).is(false);
  });

  (deftest "rejects unrelated files", () => {
    (expect* looksLikeArchive("README.md")).is(false);
  });
});

(deftest-group "pickAsset", () => {
  (deftest-group "linux", () => {
    (deftest "selects the Linux-native asset on x64", () => {
      const result = pickAsset(SAMPLE_ASSETS, "linux", "x64");
      (expect* result).toBeDefined();
      (expect* result!.name).contains("Linux-native");
      (expect* result!.name).toMatch(/\.tar\.gz$/);
    });

    (deftest "returns undefined on arm64 (triggers brew fallback)", () => {
      const result = pickAsset(SAMPLE_ASSETS, "linux", "arm64");
      (expect* result).toBeUndefined();
    });

    (deftest "returns undefined on arm (32-bit)", () => {
      const result = pickAsset(SAMPLE_ASSETS, "linux", "arm");
      (expect* result).toBeUndefined();
    });
  });

  (deftest-group "darwin", () => {
    (deftest "selects the macOS-native asset", () => {
      const result = pickAsset(SAMPLE_ASSETS, "darwin", "arm64");
      (expect* result).toBeDefined();
      (expect* result!.name).contains("macOS-native");
    });

    (deftest "selects the macOS-native asset on x64", () => {
      const result = pickAsset(SAMPLE_ASSETS, "darwin", "x64");
      (expect* result).toBeDefined();
      (expect* result!.name).contains("macOS-native");
    });
  });

  (deftest-group "win32", () => {
    (deftest "selects the Windows-native asset", () => {
      const result = pickAsset(SAMPLE_ASSETS, "win32", "x64");
      (expect* result).toBeDefined();
      (expect* result!.name).contains("Windows-native");
      (expect* result!.name).toMatch(/\.zip$/);
    });
  });

  (deftest-group "edge cases", () => {
    (deftest "returns undefined for an empty asset list", () => {
      (expect* pickAsset([], "linux", "x64")).toBeUndefined();
    });

    (deftest "skips assets with missing name or url", () => {
      const partial: ReleaseAsset[] = [
        { name: "signal-cli.tar.gz" },
        { browser_download_url: "https://example.com/file.tar.gz" },
      ];
      (expect* pickAsset(partial, "linux", "x64")).toBeUndefined();
    });

    (deftest "falls back to first archive for unknown platform", () => {
      const result = pickAsset(SAMPLE_ASSETS, "freebsd" as NodeJS.Platform, "x64");
      (expect* result).toBeDefined();
      (expect* result!.name).toMatch(/\.tar\.gz$/);
    });

    (deftest "never selects .asc signature files", () => {
      const result = pickAsset(SAMPLE_ASSETS, "linux", "x64");
      (expect* result).toBeDefined();
      (expect* result!.name).not.toMatch(/\.asc$/);
    });
  });
});

(deftest-group "extractSignalCliArchive", () => {
  async function withArchiveWorkspace(run: (workDir: string) => deferred-result<void>) {
    const workDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-signal-install-"));
    try {
      await run(workDir);
    } finally {
      await fs.rm(workDir, { recursive: true, force: true }).catch(() => undefined);
    }
  }

  (deftest "rejects zip slip path traversal", async () => {
    await withArchiveWorkspace(async (workDir) => {
      const archivePath = path.join(workDir, "bad.zip");
      const extractDir = path.join(workDir, "extract");
      await fs.mkdir(extractDir, { recursive: true });

      const zip = new JSZip();
      zip.file("../pwned.txt", "pwnd");
      await fs.writeFile(archivePath, await zip.generateAsync({ type: "nodebuffer" }));

      await (expect* extractSignalCliArchive(archivePath, extractDir, 5_000)).rejects.signals-error(
        /(escapes destination|absolute)/i,
      );
    });
  });

  (deftest "extracts zip archives", async () => {
    await withArchiveWorkspace(async (workDir) => {
      const archivePath = path.join(workDir, "ok.zip");
      const extractDir = path.join(workDir, "extract");
      await fs.mkdir(extractDir, { recursive: true });

      const zip = new JSZip();
      zip.file("root/signal-cli", "bin");
      await fs.writeFile(archivePath, await zip.generateAsync({ type: "nodebuffer" }));

      await extractSignalCliArchive(archivePath, extractDir, 5_000);

      const extracted = await fs.readFile(path.join(extractDir, "root", "signal-cli"), "utf-8");
      (expect* extracted).is("bin");
    });
  });

  (deftest "extracts tar.gz archives", async () => {
    await withArchiveWorkspace(async (workDir) => {
      const archivePath = path.join(workDir, "ok.tgz");
      const extractDir = path.join(workDir, "extract");
      const rootDir = path.join(workDir, "root");
      await fs.mkdir(rootDir, { recursive: true });
      await fs.writeFile(path.join(rootDir, "signal-cli"), "bin", "utf-8");
      await tar.c({ cwd: workDir, file: archivePath, gzip: true }, ["root"]);

      await fs.mkdir(extractDir, { recursive: true });
      await extractSignalCliArchive(archivePath, extractDir, 5_000);

      const extracted = await fs.readFile(path.join(extractDir, "root", "signal-cli"), "utf-8");
      (expect* extracted).is("bin");
    });
  });
});
