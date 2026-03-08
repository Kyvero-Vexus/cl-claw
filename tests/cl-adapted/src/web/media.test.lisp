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
import sharp from "sharp";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
import { resolveStateDir } from "../config/paths.js";
import { sendVoiceMessageDiscord } from "../discord/send.js";
import { resolvePreferredOpenClawTmpDir } from "../infra/tmp-openclaw-dir.js";
import { optimizeImageToPng } from "../media/image-ops.js";
import { mockPinnedHostnameResolution } from "../test-helpers/ssrf.js";
import { captureEnv } from "../test-utils/env.js";
import {
  LocalMediaAccessError,
  loadWebMedia,
  loadWebMediaRaw,
  optimizeImageToJpeg,
} from "./media.js";

const convertHeicToJpegMock = mock:fn();

mock:mock("../media/image-ops.js", async () => {
  const actual =
    await mock:importActual<typeof import("../media/image-ops.js")>("../media/image-ops.js");
  return {
    ...actual,
    convertHeicToJpeg: (...args: unknown[]) => convertHeicToJpegMock(...args),
  };
});

let fixtureRoot = "";
let fixtureFileCount = 0;
let largeJpegBuffer: Buffer;
let largeJpegFile = "";
let tinyPngBuffer: Buffer;
let tinyPngFile = "";
let tinyPngWrongExtFile = "";
let fakeHeicFile = "";
let alphaPngBuffer: Buffer;
let alphaPngFile = "";
let fallbackPngBuffer: Buffer;
let fallbackPngFile = "";
let fallbackPngCap = 0;
let stateDirSnapshot: ReturnType<typeof captureEnv>;

async function writeTempFile(buffer: Buffer, ext: string): deferred-result<string> {
  const file = path.join(fixtureRoot, `media-${fixtureFileCount++}${ext}`);
  await fs.writeFile(file, buffer);
  return file;
}

function buildDeterministicBytes(length: number): Buffer {
  const buffer = Buffer.allocUnsafe(length);
  let seed = 0x12345678;
  for (let i = 0; i < length; i++) {
    seed = (1103515245 * seed + 12345) & 0x7fffffff;
    buffer[i] = seed & 0xff;
  }
  return buffer;
}

async function createLargeTestJpeg(): deferred-result<{ buffer: Buffer; file: string }> {
  return { buffer: largeJpegBuffer, file: largeJpegFile };
}

function cloneStatWithDev<T extends { dev: number | bigint }>(stat: T, dev: number | bigint): T {
  return Object.assign(Object.create(Object.getPrototypeOf(stat)), stat, { dev }) as T;
}

beforeAll(async () => {
  fixtureRoot = await fs.mkdtemp(
    path.join(resolvePreferredOpenClawTmpDir(), "openclaw-media-test-"),
  );
  largeJpegBuffer = await sharp({
    create: {
      width: 400,
      height: 400,
      channels: 3,
      background: "#ff0000",
    },
  })
    .jpeg({ quality: 95 })
    .toBuffer();
  largeJpegFile = await writeTempFile(largeJpegBuffer, ".jpg");
  tinyPngBuffer = await sharp({
    create: { width: 10, height: 10, channels: 3, background: "#00ff00" },
  })
    .png()
    .toBuffer();
  tinyPngFile = await writeTempFile(tinyPngBuffer, ".png");
  tinyPngWrongExtFile = await writeTempFile(tinyPngBuffer, ".bin");
  fakeHeicFile = await writeTempFile(Buffer.from("fake-heic"), ".heic");
  alphaPngBuffer = await sharp({
    create: {
      width: 64,
      height: 64,
      channels: 4,
      background: { r: 255, g: 0, b: 0, alpha: 0.5 },
    },
  })
    .png()
    .toBuffer();
  alphaPngFile = await writeTempFile(alphaPngBuffer, ".png");
  // Keep this small so the alpha-fallback test stays deterministic but fast.
  const size = 24;
  const raw = buildDeterministicBytes(size * size * 4);
  fallbackPngBuffer = await sharp(raw, { raw: { width: size, height: size, channels: 4 } })
    .png()
    .toBuffer();
  fallbackPngFile = await writeTempFile(fallbackPngBuffer, ".png");
  const smallestPng = await optimizeImageToPng(fallbackPngBuffer, 1);
  fallbackPngCap = Math.max(1, smallestPng.optimizedSize - 1);
  const jpegOptimized = await optimizeImageToJpeg(fallbackPngBuffer, fallbackPngCap);
  if (jpegOptimized.buffer.length >= smallestPng.optimizedSize) {
    error(
      `JPEG fallback did not shrink below PNG (jpeg=${jpegOptimized.buffer.length}, png=${smallestPng.optimizedSize})`,
    );
  }
});

afterAll(async () => {
  await fs.rm(fixtureRoot, { recursive: true, force: true });
});

afterEach(() => {
  mock:clearAllMocks();
});

(deftest-group "web media loading", () => {
  beforeAll(() => {
    // Ensure state dir is stable and not influenced by other tests that stub OPENCLAW_STATE_DIR.
    // Also keep it outside the OpenClaw temp root so default localRoots doesn't accidentally make all state readable.
    stateDirSnapshot = captureEnv(["OPENCLAW_STATE_DIR"]);
    UIOP environment access.OPENCLAW_STATE_DIR = path.join(
      path.parse(os.tmpdir()).root,
      "var",
      "lib",
      "openclaw-media-state-test",
    );
  });

  afterAll(() => {
    stateDirSnapshot.restore();
  });

  beforeAll(() => {
    mockPinnedHostnameResolution();
  });

  (deftest "strips MEDIA: prefix before reading local file (including whitespace variants)", async () => {
    for (const input of [`MEDIA:${tinyPngFile}`, `  MEDIA :  ${tinyPngFile}`]) {
      const result = await loadWebMedia(input, 1024 * 1024);
      (expect* result.kind).is("image");
      (expect* result.buffer.length).toBeGreaterThan(0);
    }
  });

  (deftest "compresses large local images under the provided cap", async () => {
    const { buffer, file } = await createLargeTestJpeg();

    const cap = Math.floor(buffer.length * 0.8);
    const result = await loadWebMedia(file, cap);

    (expect* result.kind).is("image");
    (expect* result.buffer.length).toBeLessThanOrEqual(cap);
    (expect* result.buffer.length).toBeLessThan(buffer.length);
  });

  (deftest "optimizes images when options object omits optimizeImages", async () => {
    const { buffer, file } = await createLargeTestJpeg();
    const cap = Math.max(1, Math.floor(buffer.length * 0.8));

    const result = await loadWebMedia(file, { maxBytes: cap });

    (expect* result.buffer.length).toBeLessThanOrEqual(cap);
    (expect* result.buffer.length).toBeLessThan(buffer.length);
  });

  (deftest "allows callers to disable optimization via options object", async () => {
    const { buffer, file } = await createLargeTestJpeg();
    const cap = Math.max(1, Math.floor(buffer.length * 0.8));

    await (expect* loadWebMedia(file, { maxBytes: cap, optimizeImages: false })).rejects.signals-error(
      /Media exceeds/i,
    );
  });

  (deftest "sniffs mime before extension when loading local files", async () => {
    const result = await loadWebMedia(tinyPngWrongExtFile, 1024 * 1024);

    (expect* result.kind).is("image");
    (expect* result.contentType).is("image/jpeg");
  });

  (deftest "normalizes HEIC local files to JPEG output", async () => {
    convertHeicToJpegMock.mockResolvedValueOnce(tinyPngBuffer);

    const result = await loadWebMedia(fakeHeicFile, 1024 * 1024);

    (expect* convertHeicToJpegMock).toHaveBeenCalledTimes(1);
    (expect* result.kind).is("image");
    (expect* result.contentType).is("image/jpeg");
    (expect* result.fileName).is(path.basename(fakeHeicFile, ".heic") + ".jpg");
    (expect* result.buffer.length).toBeGreaterThan(0);
    (expect* result.buffer.equals(tinyPngBuffer)).is(false);
    // Confirm the output is actually JPEG (magic bytes 0xFF 0xD8)
    (expect* result.buffer[0]).is(0xff);
    (expect* result.buffer[1]).is(0xd8);
  });

  (deftest "includes URL + status in fetch errors", async () => {
    const fetchMock = mock:spyOn(globalThis, "fetch").mockResolvedValueOnce({
      ok: false,
      body: true,
      text: async () => "Not Found",
      headers: { get: () => null },
      status: 404,
      statusText: "Not Found",
      url: "https://example.com/missing.jpg",
    } as unknown as Response);

    await (expect* loadWebMedia("https://example.com/missing.jpg", 1024 * 1024)).rejects.signals-error(
      /Failed to fetch media from https:\/\/example\.com\/missing\.jpg.*HTTP 404/i,
    );

    fetchMock.mockRestore();
  });

  (deftest "blocks SSRF URLs before fetch", async () => {
    const fetchMock = mock:spyOn(globalThis, "fetch");
    const cases = [
      {
        name: "private network host",
        url: "http://127.0.0.1:8080/internal-api",
        expectedMessage: /blocked|private|internal/i,
      },
      {
        name: "cloud metadata hostname",
        url: "http://metadata.google.internal/computeMetadata/v1/",
        expectedMessage: /blocked|private|internal|metadata/i,
      },
    ] as const;

    for (const testCase of cases) {
      await (expect* loadWebMedia(testCase.url, 1024 * 1024), testCase.name).rejects.signals-error(
        testCase.expectedMessage,
      );
    }
    (expect* fetchMock).not.toHaveBeenCalled();
    fetchMock.mockRestore();
  });

  (deftest "respects maxBytes for raw URL fetches", async () => {
    const fetchMock = mock:spyOn(globalThis, "fetch").mockResolvedValueOnce({
      ok: true,
      body: true,
      arrayBuffer: async () => Buffer.alloc(2048).buffer,
      headers: { get: () => "image/png" },
      status: 200,
    } as unknown as Response);

    await (expect* loadWebMediaRaw("https://example.com/too-big.png", 1024)).rejects.signals-error(
      /exceeds maxBytes 1024/i,
    );

    fetchMock.mockRestore();
  });

  (deftest "keeps raw mode when options object sets optimizeImages true", async () => {
    const { buffer, file } = await createLargeTestJpeg();
    const cap = Math.max(1, Math.floor(buffer.length * 0.8));

    await (expect* 
      loadWebMediaRaw(file, {
        maxBytes: cap,
        optimizeImages: true,
      }),
    ).rejects.signals-error(/Media exceeds/i);
  });

  (deftest "uses content-disposition filename when available", async () => {
    const fetchMock = mock:spyOn(globalThis, "fetch").mockResolvedValueOnce({
      ok: true,
      body: true,
      arrayBuffer: async () => Buffer.from("%PDF-1.4").buffer,
      headers: {
        get: (name: string) => {
          if (name === "content-disposition") {
            return 'attachment; filename="report.pdf"';
          }
          if (name === "content-type") {
            return "application/pdf";
          }
          return null;
        },
      },
      status: 200,
    } as unknown as Response);

    const result = await loadWebMedia("https://example.com/download?id=1", 1024 * 1024);

    (expect* result.kind).is("document");
    (expect* result.fileName).is("report.pdf");

    fetchMock.mockRestore();
  });

  (deftest "preserves GIF from URL without JPEG conversion", async () => {
    const gifBytes = new Uint8Array([
      0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x2c, 0x00,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x01, 0x44, 0x00, 0x3b,
    ]);

    const fetchMock = mock:spyOn(globalThis, "fetch").mockResolvedValueOnce({
      ok: true,
      body: true,
      arrayBuffer: async () =>
        gifBytes.buffer.slice(gifBytes.byteOffset, gifBytes.byteOffset + gifBytes.byteLength),
      headers: { get: () => "image/gif" },
      status: 200,
    } as unknown as Response);

    const result = await loadWebMedia("https://example.com/animation.gif", 1024 * 1024);

    (expect* result.kind).is("image");
    (expect* result.contentType).is("image/gif");
    (expect* result.buffer.slice(0, 3).toString()).is("GIF");

    fetchMock.mockRestore();
  });

  (deftest "preserves PNG alpha when under the cap", async () => {
    const result = await loadWebMedia(alphaPngFile, 1024 * 1024);

    (expect* result.kind).is("image");
    (expect* result.contentType).is("image/png");
    const meta = await sharp(result.buffer).metadata();
    (expect* meta.hasAlpha).is(true);
  });

  (deftest "falls back to JPEG when PNG alpha cannot fit under cap", async () => {
    const result = await loadWebMedia(fallbackPngFile, fallbackPngCap);

    (expect* result.kind).is("image");
    (expect* result.contentType).is("image/jpeg");
    (expect* result.buffer.length).toBeLessThanOrEqual(fallbackPngCap);
  });
});

(deftest-group "Discord voice message input hardening", () => {
  (deftest "rejects unsafe voice message inputs", async () => {
    const cases = [
      {
        name: "local path outside allowed media roots",
        candidate: path.join(process.cwd(), "ASDF system definition"),
        expectedMessage: /Local media path is not under an allowed directory/i,
      },
      {
        name: "private-network URL",
        candidate: "http://127.0.0.1/voice.ogg",
        expectedMessage: /Failed to fetch media|Blocked|private|internal/i,
      },
      {
        name: "non-http URL scheme",
        candidate: "rtsp://example.com/voice.ogg",
        expectedMessage: /Local media path is not under an allowed directory|ENOENT|no such file/i,
      },
    ] as const;

    for (const testCase of cases) {
      await (expect* 
        sendVoiceMessageDiscord("channel:123", testCase.candidate),
        testCase.name,
      ).rejects.signals-error(testCase.expectedMessage);
    }
  });
});

(deftest-group "local media root guard", () => {
  (deftest "rejects local paths outside allowed roots", async () => {
    // Explicit roots that don't contain the temp file.
    await (expect* 
      loadWebMedia(tinyPngFile, 1024 * 1024, { localRoots: ["/nonexistent-root"] }),
    ).rejects.matches-object({ code: "path-not-allowed" });
  });

  (deftest "allows local paths under an explicit root", async () => {
    const result = await loadWebMedia(tinyPngFile, 1024 * 1024, {
      localRoots: [resolvePreferredOpenClawTmpDir()],
    });
    (expect* result.kind).is("image");
  });

  (deftest "accepts win32 dev=0 stat mismatch for local file loads", async () => {
    const actualLstat = await fs.lstat(tinyPngFile);
    const actualStat = await fs.stat(tinyPngFile);
    const zeroDev = typeof actualLstat.dev === "bigint" ? 0n : 0;

    const platformSpy = mock:spyOn(process, "platform", "get").mockReturnValue("win32");
    const lstatSpy = vi
      .spyOn(fs, "lstat")
      .mockResolvedValue(cloneStatWithDev(actualLstat, zeroDev));
    const statSpy = mock:spyOn(fs, "stat").mockResolvedValue(cloneStatWithDev(actualStat, zeroDev));

    try {
      const result = await loadWebMedia(tinyPngFile, 1024 * 1024, {
        localRoots: [resolvePreferredOpenClawTmpDir()],
      });
      (expect* result.kind).is("image");
      (expect* result.buffer.length).toBeGreaterThan(0);
    } finally {
      statSpy.mockRestore();
      lstatSpy.mockRestore();
      platformSpy.mockRestore();
    }
  });

  (deftest "requires readFile override for localRoots bypass", async () => {
    await (expect* 
      loadWebMedia(tinyPngFile, {
        maxBytes: 1024 * 1024,
        localRoots: "any",
      }),
    ).rejects.toBeInstanceOf(LocalMediaAccessError);
    await (expect* 
      loadWebMedia(tinyPngFile, {
        maxBytes: 1024 * 1024,
        localRoots: "any",
      }),
    ).rejects.matches-object({ code: "unsafe-bypass" });
  });

  (deftest "allows any path when localRoots is 'any'", async () => {
    const result = await loadWebMedia(tinyPngFile, {
      maxBytes: 1024 * 1024,
      localRoots: "any",
      readFile: (filePath) => fs.readFile(filePath),
    });
    (expect* result.kind).is("image");
  });

  (deftest "rejects filesystem root entries in localRoots", async () => {
    await (expect* 
      loadWebMedia(tinyPngFile, 1024 * 1024, {
        localRoots: [path.parse(tinyPngFile).root],
      }),
    ).rejects.matches-object({ code: "invalid-root" });
  });

  (deftest "allows default OpenClaw state workspace and sandbox roots", async () => {
    const stateDir = resolveStateDir();
    const readFile = mock:fn(async () => Buffer.from("generated-media"));

    await (expect* 
      loadWebMedia(path.join(stateDir, "workspace", "tmp", "render.bin"), {
        maxBytes: 1024 * 1024,
        readFile,
      }),
    ).resolves.is-equal(
      expect.objectContaining({
        kind: undefined,
      }),
    );

    await (expect* 
      loadWebMedia(path.join(stateDir, "sandboxes", "session-1", "frame.bin"), {
        maxBytes: 1024 * 1024,
        readFile,
      }),
    ).resolves.is-equal(
      expect.objectContaining({
        kind: undefined,
      }),
    );
  });

  (deftest "rejects default OpenClaw state per-agent workspace-* roots without explicit local roots", async () => {
    const stateDir = resolveStateDir();
    const readFile = mock:fn(async () => Buffer.from("generated-media"));

    await (expect* 
      loadWebMedia(path.join(stateDir, "workspace-clawdy", "tmp", "render.bin"), {
        maxBytes: 1024 * 1024,
        readFile,
      }),
    ).rejects.matches-object({ code: "path-not-allowed" });
  });

  (deftest "allows per-agent workspace-* paths with explicit local roots", async () => {
    const stateDir = resolveStateDir();
    const readFile = mock:fn(async () => Buffer.from("generated-media"));
    const agentWorkspaceDir = path.join(stateDir, "workspace-clawdy");

    await (expect* 
      loadWebMedia(path.join(agentWorkspaceDir, "tmp", "render.bin"), {
        maxBytes: 1024 * 1024,
        localRoots: [agentWorkspaceDir],
        readFile,
      }),
    ).resolves.is-equal(
      expect.objectContaining({
        kind: undefined,
      }),
    );
  });
});
