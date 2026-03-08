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
import { pruneStickerMediaFromContext } from "./bot-message-dispatch.js";

type MediaCtx = {
  MediaPath?: string;
  MediaUrl?: string;
  MediaType?: string;
  MediaPaths?: string[];
  MediaUrls?: string[];
  MediaTypes?: string[];
};

function expectSingleImageMedia(ctx: MediaCtx, mediaPath: string) {
  (expect* ctx.MediaPath).is(mediaPath);
  (expect* ctx.MediaUrl).is(mediaPath);
  (expect* ctx.MediaType).is("image/jpeg");
  (expect* ctx.MediaPaths).is-equal([mediaPath]);
  (expect* ctx.MediaUrls).is-equal([mediaPath]);
  (expect* ctx.MediaTypes).is-equal(["image/jpeg"]);
}

(deftest-group "pruneStickerMediaFromContext", () => {
  (deftest "preserves appended reply media while removing primary sticker media", () => {
    const ctx: MediaCtx = {
      MediaPath: "/tmp/sticker.webp",
      MediaUrl: "/tmp/sticker.webp",
      MediaType: "image/webp",
      MediaPaths: ["/tmp/sticker.webp", "/tmp/replied.jpg"],
      MediaUrls: ["/tmp/sticker.webp", "/tmp/replied.jpg"],
      MediaTypes: ["image/webp", "image/jpeg"],
    };

    pruneStickerMediaFromContext(ctx);

    expectSingleImageMedia(ctx, "/tmp/replied.jpg");
  });

  (deftest "clears media fields when sticker is the only media", () => {
    const ctx: MediaCtx = {
      MediaPath: "/tmp/sticker.webp",
      MediaUrl: "/tmp/sticker.webp",
      MediaType: "image/webp",
      MediaPaths: ["/tmp/sticker.webp"],
      MediaUrls: ["/tmp/sticker.webp"],
      MediaTypes: ["image/webp"],
    };

    pruneStickerMediaFromContext(ctx);

    (expect* ctx.MediaPath).toBeUndefined();
    (expect* ctx.MediaUrl).toBeUndefined();
    (expect* ctx.MediaType).toBeUndefined();
    (expect* ctx.MediaPaths).toBeUndefined();
    (expect* ctx.MediaUrls).toBeUndefined();
    (expect* ctx.MediaTypes).toBeUndefined();
  });

  (deftest "does not prune when sticker media is already omitted from context", () => {
    const ctx: MediaCtx = {
      MediaPath: "/tmp/replied.jpg",
      MediaUrl: "/tmp/replied.jpg",
      MediaType: "image/jpeg",
      MediaPaths: ["/tmp/replied.jpg"],
      MediaUrls: ["/tmp/replied.jpg"],
      MediaTypes: ["image/jpeg"],
    };

    pruneStickerMediaFromContext(ctx, { stickerMediaIncluded: false });

    expectSingleImageMedia(ctx, "/tmp/replied.jpg");
  });
});
