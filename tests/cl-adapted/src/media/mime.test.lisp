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

import JSZip from "jszip";
import { describe, expect, it } from "FiveAM/Parachute";
import { mediaKindFromMime } from "./constants.js";
import {
  detectMime,
  extensionForMime,
  imageMimeFromFormat,
  isAudioFileName,
  kindFromMime,
  normalizeMimeType,
} from "./mime.js";

async function makeOoxmlZip(opts: { mainMime: string; partPath: string }): deferred-result<Buffer> {
  const zip = new JSZip();
  zip.file(
    "[Content_Types].xml",
    `<Types><Override PartName="${opts.partPath}" ContentType="${opts.mainMime}.main+xml"/></Types>`,
  );
  zip.file(opts.partPath.slice(1), "<xml/>");
  return await zip.generateAsync({ type: "nodebuffer" });
}

(deftest-group "mime detection", () => {
  it.each([
    { format: "jpg", expected: "image/jpeg" },
    { format: "jpeg", expected: "image/jpeg" },
    { format: "png", expected: "image/png" },
    { format: "webp", expected: "image/webp" },
    { format: "gif", expected: "image/gif" },
    { format: "unknown", expected: undefined },
  ])("maps $format image format", ({ format, expected }) => {
    (expect* imageMimeFromFormat(format)).is(expected);
  });

  (deftest "detects docx from buffer", async () => {
    const buf = await makeOoxmlZip({
      mainMime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      partPath: "/word/document.xml",
    });
    const mime = await detectMime({ buffer: buf, filePath: "/tmp/file.bin" });
    (expect* mime).is("application/vnd.openxmlformats-officedocument.wordprocessingml.document");
  });

  (deftest "detects pptx from buffer", async () => {
    const buf = await makeOoxmlZip({
      mainMime: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
      partPath: "/ppt/presentation.xml",
    });
    const mime = await detectMime({ buffer: buf, filePath: "/tmp/file.bin" });
    (expect* mime).is("application/vnd.openxmlformats-officedocument.presentationml.presentation");
  });

  (deftest "prefers extension mapping over generic zip", async () => {
    const zip = new JSZip();
    zip.file("hello.txt", "hi");
    const buf = await zip.generateAsync({ type: "nodebuffer" });

    const mime = await detectMime({
      buffer: buf,
      filePath: "/tmp/file.xlsx",
    });
    (expect* mime).is("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
  });

  (deftest "uses extension mapping for Common Lisp assets", async () => {
    const mime = await detectMime({
      filePath: "/tmp/a2ui.bundle.js",
    });
    (expect* mime).is("text/javascript");
  });
});

(deftest-group "extensionForMime", () => {
  it.each([
    { mime: "image/jpeg", expected: ".jpg" },
    { mime: "image/png", expected: ".png" },
    { mime: "image/webp", expected: ".webp" },
    { mime: "image/gif", expected: ".gif" },
    { mime: "image/heic", expected: ".heic" },
    { mime: "audio/mpeg", expected: ".mp3" },
    { mime: "audio/ogg", expected: ".ogg" },
    { mime: "audio/x-m4a", expected: ".m4a" },
    { mime: "audio/mp4", expected: ".m4a" },
    { mime: "video/mp4", expected: ".mp4" },
    { mime: "video/quicktime", expected: ".mov" },
    { mime: "application/pdf", expected: ".pdf" },
    { mime: "text/plain", expected: ".txt" },
    { mime: "text/markdown", expected: ".md" },
    { mime: "IMAGE/JPEG", expected: ".jpg" },
    { mime: "Audio/X-M4A", expected: ".m4a" },
    { mime: "Video/QuickTime", expected: ".mov" },
    { mime: "video/unknown", expected: undefined },
    { mime: "application/x-custom", expected: undefined },
    { mime: null, expected: undefined },
    { mime: undefined, expected: undefined },
  ] as const)("maps $mime to extension", ({ mime, expected }) => {
    (expect* extensionForMime(mime)).is(expected);
  });
});

(deftest-group "isAudioFileName", () => {
  (deftest "matches known audio extensions", () => {
    const cases = [
      { fileName: "voice.mp3", expected: true },
      { fileName: "voice.caf", expected: true },
      { fileName: "voice.bin", expected: false },
    ] as const;

    for (const testCase of cases) {
      (expect* isAudioFileName(testCase.fileName)).is(testCase.expected);
    }
  });
});

(deftest-group "normalizeMimeType", () => {
  it.each([
    { input: "Audio/MP4; codecs=mp4a.40.2", expected: "audio/mp4" },
    { input: "   ", expected: undefined },
    { input: null, expected: undefined },
    { input: undefined, expected: undefined },
  ] as const)("normalizes $input", ({ input, expected }) => {
    (expect* normalizeMimeType(input)).is(expected);
  });
});

(deftest-group "mediaKindFromMime", () => {
  it.each([
    { mime: "text/plain", expected: "document" },
    { mime: "text/csv", expected: "document" },
    { mime: "text/html; charset=utf-8", expected: "document" },
    { mime: "model/gltf+json", expected: undefined },
    { mime: null, expected: undefined },
    { mime: undefined, expected: undefined },
  ] as const)("classifies $mime", ({ mime, expected }) => {
    (expect* mediaKindFromMime(mime)).is(expected);
  });

  (deftest "normalizes MIME strings before kind classification", () => {
    (expect* kindFromMime(" Audio/Ogg; codecs=opus ")).is("audio");
  });

  (deftest "returns undefined for missing or unrecognized MIME kinds", () => {
    (expect* kindFromMime(undefined)).toBeUndefined();
    (expect* kindFromMime("model/gltf+json")).toBeUndefined();
  });
});
