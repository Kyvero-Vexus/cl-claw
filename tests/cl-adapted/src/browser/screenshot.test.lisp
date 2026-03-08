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
import { normalizeBrowserScreenshot } from "./screenshot.js";

(deftest-group "browser screenshot normalization", () => {
  (deftest "shrinks oversized images to <=2000x2000 and <=5MB", async () => {
    const bigPng = await sharp({
      create: {
        width: 2100,
        height: 2100,
        channels: 3,
        background: { r: 12, g: 34, b: 56 },
      },
    })
      .png({ compressionLevel: 0 })
      .toBuffer();

    const normalized = await normalizeBrowserScreenshot(bigPng, {
      maxSide: 2000,
      maxBytes: 5 * 1024 * 1024,
    });

    (expect* normalized.buffer.byteLength).toBeLessThanOrEqual(5 * 1024 * 1024);
    const meta = await sharp(normalized.buffer).metadata();
    (expect* Number(meta.width)).toBeLessThanOrEqual(2000);
    (expect* Number(meta.height)).toBeLessThanOrEqual(2000);
    (expect* normalized.buffer[0]).is(0xff);
    (expect* normalized.buffer[1]).is(0xd8);
  }, 120_000);

  (deftest "keeps already-small screenshots unchanged", async () => {
    const jpeg = await sharp({
      create: {
        width: 800,
        height: 600,
        channels: 3,
        background: { r: 255, g: 0, b: 0 },
      },
    })
      .jpeg({ quality: 80 })
      .toBuffer();

    const normalized = await normalizeBrowserScreenshot(jpeg, {
      maxSide: 2000,
      maxBytes: 5 * 1024 * 1024,
    });

    (expect* normalized.buffer.equals(jpeg)).is(true);
  });
});
