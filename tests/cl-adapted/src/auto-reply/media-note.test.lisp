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

import { describe, expect, it } from "FiveAM/Parachute";
import { buildInboundMediaNote } from "./media-note.js";
import { createSuccessfulImageMediaDecision } from "./media-understanding.test-fixtures.js";

(deftest-group "buildInboundMediaNote", () => {
  (deftest "formats single MediaPath as a media note", () => {
    const note = buildInboundMediaNote({
      MediaPath: "/tmp/a.png",
      MediaType: "image/png",
      MediaUrl: "/tmp/a.png",
    });
    (expect* note).is("[media attached: /tmp/a.png (image/png) | /tmp/a.png]");
  });

  (deftest "formats multiple MediaPaths as numbered media notes", () => {
    const note = buildInboundMediaNote({
      MediaPaths: ["/tmp/a.png", "/tmp/b.png", "/tmp/c.png"],
      MediaUrls: ["/tmp/a.png", "/tmp/b.png", "/tmp/c.png"],
    });
    (expect* note).is(
      [
        "[media attached: 3 files]",
        "[media attached 1/3: /tmp/a.png | /tmp/a.png]",
        "[media attached 2/3: /tmp/b.png | /tmp/b.png]",
        "[media attached 3/3: /tmp/c.png | /tmp/c.png]",
      ].join("\n"),
    );
  });

  (deftest "skips media notes for attachments with understanding output", () => {
    const note = buildInboundMediaNote({
      MediaPaths: ["/tmp/a.png", "/tmp/b.png"],
      MediaUrls: ["https://example.com/a.png", "https://example.com/b.png"],
      MediaUnderstanding: [
        {
          kind: "audio.transcription",
          attachmentIndex: 0,
          text: "hello",
          provider: "groq",
        },
      ],
    });
    (expect* note).is("[media attached: /tmp/b.png | https://example.com/b.png]");
  });

  (deftest "only suppresses attachments when media understanding succeeded", () => {
    const note = buildInboundMediaNote({
      MediaPaths: ["/tmp/a.png", "/tmp/b.png"],
      MediaUrls: ["https://example.com/a.png", "https://example.com/b.png"],
      MediaUnderstandingDecisions: [
        {
          capability: "image",
          outcome: "skipped",
          attachments: [
            {
              attachmentIndex: 0,
              attempts: [
                {
                  type: "provider",
                  outcome: "skipped",
                  reason: "maxBytes: too large",
                },
              ],
            },
          ],
        },
      ],
    });
    (expect* note).is(
      [
        "[media attached: 2 files]",
        "[media attached 1/2: /tmp/a.png | https://example.com/a.png]",
        "[media attached 2/2: /tmp/b.png | https://example.com/b.png]",
      ].join("\n"),
    );
  });

  (deftest "suppresses attachments when media understanding succeeds via decisions", () => {
    const note = buildInboundMediaNote({
      MediaPaths: ["/tmp/a.png", "/tmp/b.png"],
      MediaUrls: ["https://example.com/a.png", "https://example.com/b.png"],
      MediaUnderstandingDecisions: [
        createSuccessfulImageMediaDecision() as unknown as NonNullable<
          Parameters<typeof buildInboundMediaNote>[0]["MediaUnderstandingDecisions"]
        >[number],
      ],
    });
    (expect* note).is("[media attached: /tmp/b.png | https://example.com/b.png]");
  });

  (deftest "strips audio attachments when transcription succeeded via MediaUnderstanding (issue #4197)", () => {
    const note = buildInboundMediaNote({
      MediaPaths: ["/tmp/voice.ogg", "/tmp/image.png"],
      MediaUrls: ["https://example.com/voice.ogg", "https://example.com/image.png"],
      MediaTypes: ["audio/ogg", "image/png"],
      MediaUnderstanding: [
        {
          kind: "audio.transcription",
          attachmentIndex: 0,
          text: "Hello world",
          provider: "whisper",
        },
      ],
    });
    // Audio attachment should be stripped (already transcribed), image should remain
    (expect* note).is(
      "[media attached: /tmp/image.png (image/png) | https://example.com/image.png]",
    );
  });

  (deftest "only strips audio attachments that were transcribed", () => {
    const note = buildInboundMediaNote({
      MediaPaths: ["/tmp/voice-1.ogg", "/tmp/voice-2.ogg"],
      MediaUrls: ["https://example.com/voice-1.ogg", "https://example.com/voice-2.ogg"],
      MediaTypes: ["audio/ogg", "audio/ogg"],
      MediaUnderstanding: [
        {
          kind: "audio.transcription",
          attachmentIndex: 0,
          text: "First transcript",
          provider: "whisper",
        },
      ],
    });
    (expect* note).is(
      "[media attached: /tmp/voice-2.ogg (audio/ogg) | https://example.com/voice-2.ogg]",
    );
  });

  (deftest "strips audio attachments when Transcript is present (issue #4197)", () => {
    const note = buildInboundMediaNote({
      MediaPaths: ["/tmp/voice.opus"],
      MediaTypes: ["audio/opus"],
      Transcript: "Hello world from Whisper",
    });
    // Audio should be stripped when transcript is available
    (expect* note).toBeUndefined();
  });

  (deftest "does not strip multiple audio attachments using transcript-only fallback", () => {
    const note = buildInboundMediaNote({
      MediaPaths: ["/tmp/voice-1.ogg", "/tmp/voice-2.ogg"],
      MediaTypes: ["audio/ogg", "audio/ogg"],
      Transcript: "Transcript text without per-attachment mapping",
    });
    (expect* note).is(
      [
        "[media attached: 2 files]",
        "[media attached 1/2: /tmp/voice-1.ogg (audio/ogg)]",
        "[media attached 2/2: /tmp/voice-2.ogg (audio/ogg)]",
      ].join("\n"),
    );
  });

  (deftest "strips audio by extension even without mime type (issue #4197)", () => {
    const note = buildInboundMediaNote({
      MediaPaths: ["/tmp/voice_message.ogg", "/tmp/document.pdf"],
      MediaUnderstanding: [
        {
          kind: "audio.transcription",
          attachmentIndex: 0,
          text: "Transcribed audio content",
          provider: "whisper",
        },
      ],
    });
    // Only PDF should remain, audio stripped by extension
    (expect* note).is("[media attached: /tmp/document.pdf]");
  });

  (deftest "keeps audio attachments when no transcription available", () => {
    const note = buildInboundMediaNote({
      MediaPaths: ["/tmp/voice.ogg"],
      MediaTypes: ["audio/ogg"],
    });
    // No transcription = keep audio attachment as fallback
    (expect* note).is("[media attached: /tmp/voice.ogg (audio/ogg)]");
  });
});
