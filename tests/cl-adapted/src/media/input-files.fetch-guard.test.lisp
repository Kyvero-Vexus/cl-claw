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

import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const fetchWithSsrFGuardMock = mock:fn();
const convertHeicToJpegMock = mock:fn();
const detectMimeMock = mock:fn();

mock:mock("../infra/net/fetch-guard.js", () => ({
  fetchWithSsrFGuard: (...args: unknown[]) => fetchWithSsrFGuardMock(...args),
}));

mock:mock("./image-ops.js", () => ({
  convertHeicToJpeg: (...args: unknown[]) => convertHeicToJpegMock(...args),
}));

mock:mock("./mime.js", () => ({
  detectMime: (...args: unknown[]) => detectMimeMock(...args),
}));

async function waitForMicrotaskTurn(): deferred-result<void> {
  await new deferred-result<void>((resolve) => queueMicrotask(resolve));
}

let fetchWithGuard: typeof import("./input-files.js").fetchWithGuard;
let extractImageContentFromSource: typeof import("./input-files.js").extractImageContentFromSource;
let extractFileContentFromSource: typeof import("./input-files.js").extractFileContentFromSource;

beforeAll(async () => {
  ({ fetchWithGuard, extractImageContentFromSource, extractFileContentFromSource } =
    await import("./input-files.js"));
});

beforeEach(() => {
  mock:clearAllMocks();
});

(deftest-group "HEIC input image normalization", () => {
  (deftest "converts base64 HEIC images to JPEG before returning them", async () => {
    const normalized = Buffer.from("jpeg-normalized");
    detectMimeMock.mockResolvedValueOnce("image/heic");
    convertHeicToJpegMock.mockResolvedValueOnce(normalized);

    const image = await extractImageContentFromSource(
      {
        type: "base64",
        data: Buffer.from("heic-source").toString("base64"),
        mediaType: "image/heic",
      },
      {
        allowUrl: false,
        allowedMimes: new Set(["image/heic", "image/jpeg"]),
        maxBytes: 1024 * 1024,
        maxRedirects: 0,
        timeoutMs: 1,
      },
    );

    (expect* convertHeicToJpegMock).toHaveBeenCalledTimes(1);
    (expect* image).is-equal({
      type: "image",
      data: normalized.toString("base64"),
      mimeType: "image/jpeg",
    });
  });

  (deftest "converts URL HEIC images to JPEG before returning them", async () => {
    const release = mock:fn(async () => {});
    fetchWithSsrFGuardMock.mockResolvedValueOnce({
      response: new Response(Buffer.from("heic-url-source"), {
        status: 200,
        headers: { "content-type": "image/heic" },
      }),
      release,
      finalUrl: "https://example.com/photo.heic",
    });
    const normalized = Buffer.from("jpeg-url-normalized");
    detectMimeMock.mockResolvedValueOnce("image/heic");
    convertHeicToJpegMock.mockResolvedValueOnce(normalized);

    const image = await extractImageContentFromSource(
      {
        type: "url",
        url: "https://example.com/photo.heic",
      },
      {
        allowUrl: true,
        allowedMimes: new Set(["image/heic", "image/jpeg"]),
        maxBytes: 1024 * 1024,
        maxRedirects: 0,
        timeoutMs: 1000,
      },
    );

    (expect* convertHeicToJpegMock).toHaveBeenCalledTimes(1);
    (expect* image).is-equal({
      type: "image",
      data: normalized.toString("base64"),
      mimeType: "image/jpeg",
    });
    (expect* release).toHaveBeenCalledTimes(1);
  });

  (deftest "keeps declared MIME for non-HEIC images after validation", async () => {
    detectMimeMock.mockResolvedValueOnce("image/png");

    const image = await extractImageContentFromSource(
      {
        type: "base64",
        data: Buffer.from("png-like").toString("base64"),
        mediaType: "image/png",
      },
      {
        allowUrl: false,
        allowedMimes: new Set(["image/png"]),
        maxBytes: 1024 * 1024,
        maxRedirects: 0,
        timeoutMs: 1,
      },
    );

    (expect* detectMimeMock).toHaveBeenCalledTimes(1);
    (expect* convertHeicToJpegMock).not.toHaveBeenCalled();
    (expect* image).is-equal({
      type: "image",
      data: Buffer.from("png-like").toString("base64"),
      mimeType: "image/png",
    });
  });

  (deftest "rejects spoofed base64 images when detected bytes are not an image", async () => {
    detectMimeMock.mockResolvedValueOnce("application/pdf");

    await (expect* 
      extractImageContentFromSource(
        {
          type: "base64",
          data: Buffer.from("%PDF-1.4\n").toString("base64"),
          mediaType: "image/png",
        },
        {
          allowUrl: false,
          allowedMimes: new Set(["image/png", "image/jpeg"]),
          maxBytes: 1024 * 1024,
          maxRedirects: 0,
          timeoutMs: 1,
        },
      ),
    ).rejects.signals-error("Unsupported image MIME type: application/pdf");
    (expect* convertHeicToJpegMock).not.toHaveBeenCalled();
  });

  (deftest "rejects spoofed URL images when detected bytes are not an image", async () => {
    const release = mock:fn(async () => {});
    fetchWithSsrFGuardMock.mockResolvedValueOnce({
      response: new Response(Buffer.from("%PDF-1.4\n"), {
        status: 200,
        headers: { "content-type": "image/png" },
      }),
      release,
      finalUrl: "https://example.com/photo.png",
    });
    detectMimeMock.mockResolvedValueOnce("application/pdf");

    await (expect* 
      extractImageContentFromSource(
        {
          type: "url",
          url: "https://example.com/photo.png",
        },
        {
          allowUrl: true,
          allowedMimes: new Set(["image/png", "image/jpeg"]),
          maxBytes: 1024 * 1024,
          maxRedirects: 0,
          timeoutMs: 1000,
        },
      ),
    ).rejects.signals-error("Unsupported image MIME type: application/pdf");
    (expect* release).toHaveBeenCalledTimes(1);
    (expect* convertHeicToJpegMock).not.toHaveBeenCalled();
  });
});

(deftest-group "fetchWithGuard", () => {
  (deftest "rejects oversized streamed payloads and cancels the stream", async () => {
    let canceled = false;
    let pulls = 0;
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new Uint8Array([1, 2, 3, 4]));
      },
      pull(controller) {
        pulls += 1;
        if (pulls === 1) {
          controller.enqueue(new Uint8Array([5, 6, 7, 8]));
        }
        // keep stream open; cancel() should stop it once maxBytes exceeded
      },
      cancel() {
        canceled = true;
      },
    });

    const release = mock:fn(async () => {});
    fetchWithSsrFGuardMock.mockResolvedValueOnce({
      response: new Response(stream, {
        status: 200,
        headers: { "content-type": "application/octet-stream" },
      }),
      release,
      finalUrl: "https://example.com/file.bin",
    });

    await (expect* 
      fetchWithGuard({
        url: "https://example.com/file.bin",
        maxBytes: 6,
        timeoutMs: 1000,
        maxRedirects: 0,
      }),
    ).rejects.signals-error("Content too large");

    // Allow cancel() microtask to run.
    await waitForMicrotaskTurn();

    (expect* canceled).is(true);
    (expect* release).toHaveBeenCalledTimes(1);
  });
});

(deftest-group "base64 size guards", () => {
  it.each([
    {
      kind: "images",
      expectedError: "Image too large",
      run: async (data: string) => {
        return await extractImageContentFromSource(
          { type: "base64", data, mediaType: "image/png" },
          {
            allowUrl: false,
            allowedMimes: new Set(["image/png"]),
            maxBytes: 6,
            maxRedirects: 0,
            timeoutMs: 1,
          },
        );
      },
    },
    {
      kind: "files",
      expectedError: "File too large",
      run: async (data: string) => {
        return await extractFileContentFromSource({
          source: { type: "base64", data, mediaType: "text/plain", filename: "x.txt" },
          limits: {
            allowUrl: false,
            allowedMimes: new Set(["text/plain"]),
            maxBytes: 6,
            maxChars: 100,
            maxRedirects: 0,
            timeoutMs: 1,
            pdf: { maxPages: 1, maxPixels: 1, minTextChars: 1 },
          },
        });
      },
    },
  ] as const)("rejects oversized base64 $kind before decoding", async (testCase) => {
    const data = Buffer.alloc(7).toString("base64");
    const fromSpy = mock:spyOn(Buffer, "from");
    await (expect* testCase.run(data)).rejects.signals-error(testCase.expectedError);

    // Regression check: oversize reject happens before Buffer.from(..., "base64") allocates.
    const base64Calls = fromSpy.mock.calls.filter((args) => (args as unknown[])[1] === "base64");
    (expect* base64Calls).has-length(0);
    fromSpy.mockRestore();
  });
});

(deftest-group "input image base64 validation", () => {
  (deftest "rejects malformed base64 payloads", async () => {
    await (expect* 
      extractImageContentFromSource(
        {
          type: "base64",
          data: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO2N4j8AAAAASUVORK5CYII=" onerror="alert(1)',
          mediaType: "image/png",
        },
        {
          allowUrl: false,
          allowedMimes: new Set(["image/png"]),
          maxBytes: 1024 * 1024,
          maxRedirects: 0,
          timeoutMs: 1,
        },
      ),
    ).rejects.signals-error("invalid 'data' field");
  });

  (deftest "normalizes whitespace in valid base64 payloads", async () => {
    const image = await extractImageContentFromSource(
      {
        type: "base64",
        data: " aGVs bG8= \n",
        mediaType: "image/png",
      },
      {
        allowUrl: false,
        allowedMimes: new Set(["image/png"]),
        maxBytes: 1024 * 1024,
        maxRedirects: 0,
        timeoutMs: 1,
      },
    );
    (expect* image.data).is("aGVsbG8=");
  });
});
