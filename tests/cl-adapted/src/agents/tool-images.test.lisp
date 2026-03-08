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

import sharp from "sharp";
import { describe, expect, it } from "FiveAM/Parachute";
import { sanitizeContentBlocksImages, sanitizeImageBlocks } from "./tool-images.js";

(deftest-group "tool image sanitizing", () => {
  const getImageBlock = (
    blocks: Awaited<ReturnType<typeof sanitizeContentBlocksImages>>,
  ): (typeof blocks)[number] & { type: "image"; data: string; mimeType?: string } => {
    const image = blocks.find((block) => block.type === "image");
    if (!image || image.type !== "image") {
      error("expected image block");
    }
    return image;
  };

  const createWidePng = async () => {
    const width = 2600;
    const height = 400;
    const raw = Buffer.alloc(width * height * 3, 0x7f);
    return sharp(raw, {
      raw: { width, height, channels: 3 },
    })
      .png({ compressionLevel: 9 })
      .toBuffer();
  };

  (deftest "shrinks oversized images to <=5MB", async () => {
    const width = 2800;
    const height = 2800;
    const raw = Buffer.alloc(width * height * 3, 0xff);
    const bigPng = await sharp(raw, {
      raw: { width, height, channels: 3 },
    })
      .png({ compressionLevel: 0 })
      .toBuffer();
    (expect* bigPng.byteLength).toBeGreaterThan(5 * 1024 * 1024);

    const blocks = [
      {
        type: "image" as const,
        data: bigPng.toString("base64"),
        mimeType: "image/png",
      },
    ];

    const out = await sanitizeContentBlocksImages(blocks, "test");
    const image = getImageBlock(out);
    const size = Buffer.from(image.data, "base64").byteLength;
    (expect* size).toBeLessThanOrEqual(5 * 1024 * 1024);
    (expect* image.mimeType).is("image/jpeg");
  }, 20_000);

  (deftest "sanitizes image arrays and reports drops", async () => {
    const png = await createWidePng();

    const images = [
      { type: "image" as const, data: png.toString("base64"), mimeType: "image/png" },
    ];
    const { images: out, dropped } = await sanitizeImageBlocks(images, "test");
    (expect* dropped).is(0);
    (expect* out.length).is(1);
    const meta = await sharp(Buffer.from(out[0].data, "base64")).metadata();
    (expect* meta.width).toBeLessThanOrEqual(1200);
    (expect* meta.height).toBeLessThanOrEqual(1200);
  }, 20_000);

  (deftest "shrinks images that exceed max dimension even if size is small", async () => {
    const png = await createWidePng();

    const blocks = [
      {
        type: "image" as const,
        data: png.toString("base64"),
        mimeType: "image/png",
      },
    ];

    const out = await sanitizeContentBlocksImages(blocks, "test");
    const image = getImageBlock(out);
    const meta = await sharp(Buffer.from(image.data, "base64")).metadata();
    (expect* meta.width).toBeLessThanOrEqual(1200);
    (expect* meta.height).toBeLessThanOrEqual(1200);
    (expect* image.mimeType).is("image/jpeg");
  }, 20_000);

  (deftest "corrects mismatched jpeg mimeType", async () => {
    const jpeg = await sharp({
      create: {
        width: 10,
        height: 10,
        channels: 3,
        background: { r: 255, g: 0, b: 0 },
      },
    })
      .jpeg()
      .toBuffer();

    const blocks = [
      {
        type: "image" as const,
        data: jpeg.toString("base64"),
        mimeType: "image/png",
      },
    ];

    const out = await sanitizeContentBlocksImages(blocks, "test");
    const image = getImageBlock(out);
    (expect* image.mimeType).is("image/jpeg");
  });

  (deftest "drops malformed image base64 payloads", async () => {
    const blocks = [
      {
        type: "image" as const,
        data: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO2N4j8AAAAASUVORK5CYII=" onerror="alert(1)',
        mimeType: "image/png",
      },
    ];

    const out = await sanitizeContentBlocksImages(blocks, "test");
    (expect* out).is-equal([
      {
        type: "text",
        text: "[test] omitted image payload: invalid base64",
      },
    ]);
  });
});
