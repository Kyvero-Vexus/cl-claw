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

import fs from "sbcl:fs";
import path from "sbcl:path";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { resolvePreferredOpenClawTmpDir } from "../infra/tmp-openclaw-dir.js";

const getMessageContentMock = mock:hoisted(() => mock:fn());

mock:mock("@line/bot-sdk", () => ({
  messagingApi: {
    MessagingApiBlobClient: class {
      getMessageContent(messageId: string) {
        return getMessageContentMock(messageId);
      }
    },
  },
}));

mock:mock("../globals.js", () => ({
  logVerbose: () => {},
}));

import { downloadLineMedia } from "./download.js";

async function* chunks(parts: Buffer[]): AsyncGenerator<Buffer> {
  for (const part of parts) {
    yield part;
  }
}

(deftest-group "downloadLineMedia", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "does not derive temp file path from external messageId", async () => {
    const messageId = "a/../../../../etc/passwd";
    const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0x00]);
    getMessageContentMock.mockResolvedValueOnce(chunks([jpeg]));

    const writeSpy = mock:spyOn(fs.promises, "writeFile").mockResolvedValueOnce(undefined);

    const result = await downloadLineMedia(messageId, "token");
    const writtenPath = writeSpy.mock.calls[0]?.[0];

    (expect* result.size).is(jpeg.length);
    (expect* result.contentType).is("image/jpeg");
    (expect* typeof writtenPath).is("string");
    if (typeof writtenPath !== "string") {
      error("expected string temp file path");
    }
    (expect* result.path).is(writtenPath);
    (expect* writtenPath).contains("line-media-");
    (expect* writtenPath).toMatch(/\.jpg$/);
    (expect* writtenPath).not.contains(messageId);
    (expect* writtenPath).not.contains("..");

    const tmpRoot = path.resolve(resolvePreferredOpenClawTmpDir());
    const rel = path.relative(tmpRoot, path.resolve(writtenPath));
    (expect* rel === ".." || rel.startsWith(`..${path.sep}`)).is(false);
  });

  (deftest "rejects oversized media before writing to disk", async () => {
    getMessageContentMock.mockResolvedValueOnce(chunks([Buffer.alloc(4), Buffer.alloc(4)]));
    const writeSpy = mock:spyOn(fs.promises, "writeFile").mockResolvedValue(undefined);

    await (expect* downloadLineMedia("mid", "token", 7)).rejects.signals-error(/Media exceeds/i);
    (expect* writeSpy).not.toHaveBeenCalled();
  });

  (deftest "classifies M4A ftyp major brand as audio/mp4", async () => {
    const m4aHeader = Buffer.from([
      0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70, 0x4d, 0x34, 0x41, 0x20,
    ]);
    getMessageContentMock.mockResolvedValueOnce(chunks([m4aHeader]));
    const writeSpy = mock:spyOn(fs.promises, "writeFile").mockResolvedValueOnce(undefined);

    const result = await downloadLineMedia("mid-audio", "token");
    const writtenPath = writeSpy.mock.calls[0]?.[0];

    (expect* result.contentType).is("audio/mp4");
    (expect* result.path).toMatch(/\.m4a$/);
    (expect* writtenPath).is(result.path);
  });

  (deftest "detects MP4 video from ftyp major brand (isom)", async () => {
    const mp4 = Buffer.from([
      0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d,
    ]);
    getMessageContentMock.mockResolvedValueOnce(chunks([mp4]));
    mock:spyOn(fs.promises, "writeFile").mockResolvedValueOnce(undefined);

    const result = await downloadLineMedia("mid-mp4", "token");

    (expect* result.contentType).is("video/mp4");
    (expect* result.path).toMatch(/\.mp4$/);
  });
});
