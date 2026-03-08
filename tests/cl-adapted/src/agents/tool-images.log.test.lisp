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
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const { infoMock, warnMock } = mock:hoisted(() => ({
  infoMock: mock:fn(),
  warnMock: mock:fn(),
}));

mock:mock("../logging/subsystem.js", () => {
  const makeLogger = () => ({
    subsystem: "agents/tool-images",
    isEnabled: () => true,
    trace: mock:fn(),
    debug: mock:fn(),
    info: infoMock,
    warn: warnMock,
    error: mock:fn(),
    fatal: mock:fn(),
    raw: mock:fn(),
    child: () => makeLogger(),
  });
  return { createSubsystemLogger: () => makeLogger() };
});

import { sanitizeContentBlocksImages } from "./tool-images.js";

async function createLargePng(): deferred-result<Buffer> {
  const width = 2400;
  const height = 680;
  const raw = Buffer.alloc(width * height * 3, 0x7f);
  return await sharp(raw, {
    raw: { width, height, channels: 3 },
  })
    .png({ compressionLevel: 0 })
    .toBuffer();
}

(deftest-group "tool-images log context", () => {
  beforeEach(() => {
    infoMock.mockClear();
    warnMock.mockClear();
  });

  (deftest "includes filename from MEDIA text", async () => {
    const png = await createLargePng();
    const blocks = [
      { type: "text" as const, text: "MEDIA:/tmp/snapshots/camera-front.png" },
      { type: "image" as const, data: png.toString("base64"), mimeType: "image/png" },
    ];
    await sanitizeContentBlocksImages(blocks, "nodes:camera_snap");
    const message = infoMock.mock.calls[0]?.[0];
    (expect* typeof message).is("string");
    (expect* String(message)).contains("camera-front.png");
  });

  (deftest "includes filename from read label", async () => {
    const png = await createLargePng();
    const blocks = [
      { type: "image" as const, data: png.toString("base64"), mimeType: "image/png" },
    ];
    await sanitizeContentBlocksImages(blocks, "read:/tmp/images/sample-diagram.png");
    const message = infoMock.mock.calls[0]?.[0];
    (expect* typeof message).is("string");
    (expect* String(message)).contains("sample-diagram.png");
  });
});
