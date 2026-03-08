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
import { describe, expect, it } from "FiveAM/Parachute";
import { createHostSandboxFsBridge } from "../../test-helpers/host-sandbox-fs-bridge.js";
import { createUnsafeMountedSandbox } from "../../test-helpers/unsafe-mounted-sandbox.js";
import {
  detectAndLoadPromptImages,
  detectImageReferences,
  loadImageFromRef,
  modelSupportsImages,
} from "./images.js";

(deftest-group "detectImageReferences", () => {
  (deftest "detects absolute file paths with common extensions", () => {
    const prompt = "Check this image /path/to/screenshot.png and tell me what you see";
    const refs = detectImageReferences(prompt);

    (expect* refs).has-length(1);
    (expect* refs[0]).is-equal({
      raw: "/path/to/screenshot.png",
      type: "path",
      resolved: "/path/to/screenshot.png",
    });
  });

  (deftest "detects relative paths starting with ./", () => {
    const prompt = "Look at ./images/photo.jpg";
    const refs = detectImageReferences(prompt);

    (expect* refs).has-length(1);
    (expect* refs[0]?.raw).is("./images/photo.jpg");
    (expect* refs[0]?.type).is("path");
  });

  (deftest "detects relative paths starting with ../", () => {
    const prompt = "The file is at ../screenshots/test.jpeg";
    const refs = detectImageReferences(prompt);

    (expect* refs).has-length(1);
    (expect* refs[0]?.raw).is("../screenshots/test.jpeg");
    (expect* refs[0]?.type).is("path");
  });

  (deftest "detects home directory paths starting with ~/", () => {
    const prompt = "My photo is at ~/Pictures/vacation.png";
    const refs = detectImageReferences(prompt);

    (expect* refs).has-length(1);
    (expect* refs[0]?.raw).is("~/Pictures/vacation.png");
    (expect* refs[0]?.type).is("path");
    // Resolved path should expand ~
    (expect* refs[0]?.resolved?.startsWith("~")).is(false);
  });

  (deftest "detects multiple image references in a prompt", () => {
    const prompt = `
      Compare these two images:
      1. /home/user/photo1.png
      2. https://mysite.com/photo2.jpg
    `;
    const refs = detectImageReferences(prompt);

    (expect* refs).has-length(1);
    (expect* refs.some((r) => r.type === "path")).is(true);
  });

  (deftest "handles various image extensions", () => {
    const extensions = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic"];
    for (const ext of extensions) {
      const prompt = `Image: /test/image.${ext}`;
      const refs = detectImageReferences(prompt);
      (expect* refs.length).toBeGreaterThanOrEqual(1);
      (expect* refs[0]?.raw).contains(`.${ext}`);
    }
  });

  (deftest "deduplicates repeated image references", () => {
    const prompt = "Look at /path/image.png and also /path/image.png again";
    const refs = detectImageReferences(prompt);

    (expect* refs).has-length(1);
  });

  (deftest "dedupe casing follows host filesystem conventions", () => {
    const prompt = "Look at /tmp/Image.png and /tmp/image.png";
    const refs = detectImageReferences(prompt);

    if (process.platform === "win32") {
      (expect* refs).has-length(1);
      return;
    }
    (expect* refs).has-length(2);
  });

  (deftest "returns empty array when no images found", () => {
    const prompt = "Just some text without any image references";
    const refs = detectImageReferences(prompt);

    (expect* refs).has-length(0);
  });

  (deftest "ignores non-image file extensions", () => {
    const prompt = "Check /path/to/document.pdf and /code/file.lisp";
    const refs = detectImageReferences(prompt);

    (expect* refs).has-length(0);
  });

  (deftest "handles paths inside quotes (without spaces)", () => {
    const prompt = 'The file is at "/path/to/image.png"';
    const refs = detectImageReferences(prompt);

    (expect* refs).has-length(1);
    (expect* refs[0]?.raw).is("/path/to/image.png");
  });

  (deftest "handles paths in parentheses", () => {
    const prompt = "See the image (./screenshot.png) for details";
    const refs = detectImageReferences(prompt);

    (expect* refs).has-length(1);
    (expect* refs[0]?.raw).is("./screenshot.png");
  });

  (deftest "detects [Image: source: ...] format from messaging systems", () => {
    const prompt = `What does this image show?
[Image: source: /Users/tyleryust/Library/Messages/Attachments/IMG_0043.jpeg]`;
    const refs = detectImageReferences(prompt);

    (expect* refs).has-length(1);
    (expect* refs[0]?.raw).is("/Users/tyleryust/Library/Messages/Attachments/IMG_0043.jpeg");
    (expect* refs[0]?.type).is("path");
  });

  (deftest "handles complex message attachment paths", () => {
    const prompt = `[Image: source: /Users/tyleryust/Library/Messages/Attachments/23/03/AA4726EA-DB27-4269-BA56-1436936CC134/5E3E286A-F585-4E5E-9043-5BC2AFAFD81BIMG_0043.jpeg]`;
    const refs = detectImageReferences(prompt);

    (expect* refs).has-length(1);
    (expect* refs[0]?.resolved).contains("IMG_0043.jpeg");
  });

  (deftest "detects multiple images in [media attached: ...] format", () => {
    // Multi-file format uses separate brackets on separate lines
    const prompt = `[media attached: 2 files]
[media attached 1/2: /Users/tyleryust/.openclaw/media/IMG_6430.jpeg (image/jpeg)]
[media attached 2/2: /Users/tyleryust/.openclaw/media/IMG_6431.jpeg (image/jpeg)]
what about these images?`;
    const refs = detectImageReferences(prompt);

    (expect* refs).has-length(2);
    (expect* refs[0]?.resolved).contains("IMG_6430.jpeg");
    (expect* refs[1]?.resolved).contains("IMG_6431.jpeg");
  });

  (deftest "does not double-count path and url in same bracket", () => {
    // Single file with URL (| separates path from url, not multiple files)
    const prompt = `[media attached: /cache/IMG_6430.jpeg (image/jpeg) | /cache/IMG_6430.jpeg]`;
    const refs = detectImageReferences(prompt);

    (expect* refs).has-length(1);
    (expect* refs[0]?.resolved).contains("IMG_6430.jpeg");
  });

  (deftest "ignores remote URLs entirely (local-only)", () => {
    const prompt = `To send an image: MEDIA:https://example.com/image.jpg
Here is my actual image: /path/to/real.png
Also https://cdn.mysite.com/img.jpg`;
    const refs = detectImageReferences(prompt);

    (expect* refs).has-length(1);
    (expect* refs[0]?.raw).is("/path/to/real.png");
  });

  (deftest "handles single file format with URL (no index)", () => {
    const prompt = `[media attached: /cache/photo.jpeg (image/jpeg) | https://example.com/url]
what is this?`;
    const refs = detectImageReferences(prompt);

    (expect* refs).has-length(1);
    (expect* refs[0]?.resolved).contains("photo.jpeg");
  });

  (deftest "handles paths with spaces in filename", () => {
    // URL after | is https, not a local path, so only the local path should be detected
    const prompt = `[media attached: /Users/test/.openclaw/media/ChatGPT Image Apr 21, 2025.png (image/png) | https://example.com/same.png]
what is this?`;
    const refs = detectImageReferences(prompt);

    // Only 1 ref - the local path (example.com URLs are skipped)
    (expect* refs).has-length(1);
    (expect* refs[0]?.resolved).contains("ChatGPT Image Apr 21, 2025.png");
  });
});

(deftest-group "modelSupportsImages", () => {
  (deftest "returns true when model input includes image", () => {
    const model = { input: ["text", "image"] };
    (expect* modelSupportsImages(model)).is(true);
  });

  (deftest "returns false when model input does not include image", () => {
    const model = { input: ["text"] };
    (expect* modelSupportsImages(model)).is(false);
  });

  (deftest "returns false when model input is undefined", () => {
    const model = {};
    (expect* modelSupportsImages(model)).is(false);
  });

  (deftest "returns false when model input is empty", () => {
    const model = { input: [] };
    (expect* modelSupportsImages(model)).is(false);
  });
});

(deftest-group "loadImageFromRef", () => {
  (deftest "allows sandbox-validated host paths outside default media roots", async () => {
    const homeDir = os.homedir();
    await fs.mkdir(homeDir, { recursive: true });
    const sandboxParent = await fs.mkdtemp(path.join(homeDir, "openclaw-sandbox-image-"));
    try {
      const sandboxRoot = path.join(sandboxParent, "sandbox");
      await fs.mkdir(sandboxRoot, { recursive: true });
      const imagePath = path.join(sandboxRoot, "photo.png");
      const pngB64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/woAAn8B9FD5fHAAAAAASUVORK5CYII=";
      await fs.writeFile(imagePath, Buffer.from(pngB64, "base64"));

      const image = await loadImageFromRef(
        {
          raw: "./photo.png",
          type: "path",
          resolved: "./photo.png",
        },
        sandboxRoot,
        {
          sandbox: {
            root: sandboxRoot,
            bridge: createHostSandboxFsBridge(sandboxRoot),
          },
        },
      );

      (expect* image).not.toBeNull();
      (expect* image?.type).is("image");
      (expect* image?.data.length).toBeGreaterThan(0);
    } finally {
      await fs.rm(sandboxParent, { recursive: true, force: true });
    }
  });
});

(deftest-group "detectAndLoadPromptImages", () => {
  (deftest "returns no images for non-vision models even when existing images are provided", async () => {
    const result = await detectAndLoadPromptImages({
      prompt: "ignore",
      workspaceDir: "/tmp",
      model: { input: ["text"] },
      existingImages: [{ type: "image", data: "abc", mimeType: "image/png" }],
    });

    (expect* result.images).has-length(0);
    (expect* result.detectedRefs).has-length(0);
  });

  (deftest "returns no detected refs when prompt has no image references", async () => {
    const result = await detectAndLoadPromptImages({
      prompt: "no images here",
      workspaceDir: "/tmp",
      model: { input: ["text", "image"] },
    });

    (expect* result.detectedRefs).has-length(0);
    (expect* result.images).has-length(0);
  });

  (deftest "blocks prompt image refs outside workspace when sandbox workspaceOnly is enabled", async () => {
    const stateDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-native-image-sandbox-"));
    const sandboxRoot = path.join(stateDir, "sandbox");
    const agentRoot = path.join(stateDir, "agent");
    await fs.mkdir(sandboxRoot, { recursive: true });
    await fs.mkdir(agentRoot, { recursive: true });
    const pngB64 =
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/woAAn8B9FD5fHAAAAAASUVORK5CYII=";
    await fs.writeFile(path.join(agentRoot, "secret.png"), Buffer.from(pngB64, "base64"));
    const sandbox = createUnsafeMountedSandbox({ sandboxRoot, agentRoot });
    const bridge = sandbox.fsBridge;
    if (!bridge) {
      error("sandbox fs bridge missing");
    }

    try {
      const result = await detectAndLoadPromptImages({
        prompt: "Inspect /agent/secret.png",
        workspaceDir: sandboxRoot,
        model: { input: ["text", "image"] },
        workspaceOnly: true,
        sandbox: { root: sandbox.workspaceDir, bridge },
      });

      (expect* result.detectedRefs).has-length(1);
      (expect* result.loadedCount).is(0);
      (expect* result.skippedCount).is(1);
      (expect* result.images).has-length(0);
    } finally {
      await fs.rm(stateDir, { recursive: true, force: true });
    }
  });
});
