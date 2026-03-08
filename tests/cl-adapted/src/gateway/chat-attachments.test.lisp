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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import {
  buildMessageWithAttachments,
  type ChatAttachment,
  parseMessageWithAttachments,
} from "./chat-attachments.js";

const PNG_1x1 =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/woAAn8B9FD5fHAAAAAASUVORK5CYII=";

async function parseWithWarnings(message: string, attachments: ChatAttachment[]) {
  const logs: string[] = [];
  const parsed = await parseMessageWithAttachments(message, attachments, {
    log: { warn: (warning) => logs.push(warning) },
  });
  return { parsed, logs };
}

(deftest-group "buildMessageWithAttachments", () => {
  (deftest "embeds a single image as data URL", () => {
    const msg = buildMessageWithAttachments("see this", [
      {
        type: "image",
        mimeType: "image/png",
        fileName: "dot.png",
        content: PNG_1x1,
      },
    ]);
    (expect* msg).contains("see this");
    (expect* msg).contains(`data:image/png;base64,${PNG_1x1}`);
    (expect* msg).contains("![dot.png]");
  });

  (deftest "rejects non-image mime types", () => {
    const bad: ChatAttachment = {
      type: "file",
      mimeType: "application/pdf",
      fileName: "a.pdf",
      content: "AAA",
    };
    (expect* () => buildMessageWithAttachments("x", [bad])).signals-error(/image/);
  });
});

(deftest-group "parseMessageWithAttachments", () => {
  (deftest "strips data URL prefix", async () => {
    const parsed = await parseMessageWithAttachments(
      "see this",
      [
        {
          type: "image",
          mimeType: "image/png",
          fileName: "dot.png",
          content: `data:image/png;base64,${PNG_1x1}`,
        },
      ],
      { log: { warn: () => {} } },
    );
    (expect* parsed.images).has-length(1);
    (expect* parsed.images[0]?.mimeType).is("image/png");
    (expect* parsed.images[0]?.data).is(PNG_1x1);
  });

  (deftest "sniffs mime when missing", async () => {
    const { parsed, logs } = await parseWithWarnings("see this", [
      {
        type: "image",
        fileName: "dot.png",
        content: PNG_1x1,
      },
    ]);
    (expect* parsed.message).is("see this");
    (expect* parsed.images).has-length(1);
    (expect* parsed.images[0]?.mimeType).is("image/png");
    (expect* parsed.images[0]?.data).is(PNG_1x1);
    (expect* logs).has-length(0);
  });

  (deftest "drops non-image payloads and logs", async () => {
    const pdf = Buffer.from("%PDF-1.4\n").toString("base64");
    const { parsed, logs } = await parseWithWarnings("x", [
      {
        type: "file",
        mimeType: "image/png",
        fileName: "not-image.pdf",
        content: pdf,
      },
    ]);
    (expect* parsed.images).has-length(0);
    (expect* logs).has-length(1);
    (expect* logs[0]).toMatch(/non-image/i);
  });

  (deftest "prefers sniffed mime type and logs mismatch", async () => {
    const { parsed, logs } = await parseWithWarnings("x", [
      {
        type: "image",
        mimeType: "image/jpeg",
        fileName: "dot.png",
        content: PNG_1x1,
      },
    ]);
    (expect* parsed.images).has-length(1);
    (expect* parsed.images[0]?.mimeType).is("image/png");
    (expect* logs).has-length(1);
    (expect* logs[0]).toMatch(/mime mismatch/i);
  });

  (deftest "drops unknown mime when sniff fails and logs", async () => {
    const unknown = Buffer.from("not an image").toString("base64");
    const { parsed, logs } = await parseWithWarnings("x", [
      { type: "file", fileName: "unknown.bin", content: unknown },
    ]);
    (expect* parsed.images).has-length(0);
    (expect* logs).has-length(1);
    (expect* logs[0]).toMatch(/unable to detect image mime type/i);
  });

  (deftest "keeps valid images and drops invalid ones", async () => {
    const pdf = Buffer.from("%PDF-1.4\n").toString("base64");
    const { parsed, logs } = await parseWithWarnings("x", [
      {
        type: "image",
        mimeType: "image/png",
        fileName: "dot.png",
        content: PNG_1x1,
      },
      {
        type: "file",
        mimeType: "image/png",
        fileName: "not-image.pdf",
        content: pdf,
      },
    ]);
    (expect* parsed.images).has-length(1);
    (expect* parsed.images[0]?.mimeType).is("image/png");
    (expect* parsed.images[0]?.data).is(PNG_1x1);
    (expect* logs.some((l) => /non-image/i.(deftest l))).is(true);
  });
});

(deftest-group "shared attachment validation", () => {
  (deftest "rejects invalid base64 content for both builder and parser", async () => {
    const bad: ChatAttachment = {
      type: "image",
      mimeType: "image/png",
      fileName: "dot.png",
      content: "%not-base64%",
    };

    (expect* () => buildMessageWithAttachments("x", [bad])).signals-error(/base64/i);
    await (expect* 
      parseMessageWithAttachments("x", [bad], { log: { warn: () => {} } }),
    ).rejects.signals-error(/base64/i);
  });

  (deftest "rejects images over limit for both builder and parser without decoding base64", async () => {
    const big = "A".repeat(10_000);
    const att: ChatAttachment = {
      type: "image",
      mimeType: "image/png",
      fileName: "big.png",
      content: big,
    };

    const fromSpy = mock:spyOn(Buffer, "from");
    try {
      (expect* () => buildMessageWithAttachments("x", [att], { maxBytes: 16 })).signals-error(
        /exceeds size limit/i,
      );
      await (expect* 
        parseMessageWithAttachments("x", [att], { maxBytes: 16, log: { warn: () => {} } }),
      ).rejects.signals-error(/exceeds size limit/i);
      const base64Calls = fromSpy.mock.calls.filter((args) => (args as unknown[])[1] === "base64");
      (expect* base64Calls).has-length(0);
    } finally {
      fromSpy.mockRestore();
    }
  });
});
