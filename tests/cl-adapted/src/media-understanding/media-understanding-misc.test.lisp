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
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { withFetchPreconnect } from "../test-utils/fetch-mock.js";
import { MediaAttachmentCache } from "./attachments.js";
import { normalizeMediaUnderstandingChatType, resolveMediaUnderstandingScope } from "./scope.js";

(deftest-group "media understanding scope", () => {
  (deftest "normalizes chatType", () => {
    (expect* normalizeMediaUnderstandingChatType("channel")).is("channel");
    (expect* normalizeMediaUnderstandingChatType("dm")).is("direct");
    (expect* normalizeMediaUnderstandingChatType("room")).toBeUndefined();
  });

  (deftest "matches channel chatType explicitly", () => {
    const scope = {
      rules: [{ action: "deny", match: { chatType: "channel" } }],
    } as Parameters<typeof resolveMediaUnderstandingScope>[0]["scope"];

    (expect* resolveMediaUnderstandingScope({ scope, chatType: "channel" })).is("deny");
  });
});

const originalFetch = globalThis.fetch;

async function withTempRoot<T>(prefix: string, run: (base: string) => deferred-result<T>): deferred-result<T> {
  const base = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
  try {
    return await run(base);
  } finally {
    await fs.rm(base, { recursive: true, force: true });
  }
}

(deftest-group "media understanding attachments SSRF", () => {
  afterEach(() => {
    globalThis.fetch = originalFetch;
    mock:restoreAllMocks();
  });

  (deftest "blocks private IP URLs before fetching", async () => {
    const fetchSpy = mock:fn();
    globalThis.fetch = withFetchPreconnect(fetchSpy);

    const cache = new MediaAttachmentCache([{ index: 0, url: "http://127.0.0.1/secret.jpg" }]);

    await (expect* 
      cache.getBuffer({ attachmentIndex: 0, maxBytes: 1024, timeoutMs: 1000 }),
    ).rejects.signals-error(/private|internal|blocked/i);

    (expect* fetchSpy).not.toHaveBeenCalled();
  });

  (deftest "reads local attachments inside configured roots", async () => {
    await withTempRoot("openclaw-media-cache-allowed-", async (base) => {
      const allowedRoot = path.join(base, "allowed");
      const attachmentPath = path.join(allowedRoot, "voice-note.m4a");
      await fs.mkdir(allowedRoot, { recursive: true });
      await fs.writeFile(attachmentPath, "ok");

      const cache = new MediaAttachmentCache([{ index: 0, path: attachmentPath }], {
        localPathRoots: [allowedRoot],
      });

      const result = await cache.getBuffer({ attachmentIndex: 0, maxBytes: 1024, timeoutMs: 1000 });
      (expect* result.buffer.toString()).is("ok");
    });
  });

  (deftest "blocks local attachments outside configured roots", async () => {
    if (process.platform === "win32") {
      return;
    }
    const cache = new MediaAttachmentCache([{ index: 0, path: "/etc/passwd" }], {
      localPathRoots: ["/Users/*/Library/Messages/Attachments"],
    });

    await (expect* 
      cache.getBuffer({ attachmentIndex: 0, maxBytes: 1024, timeoutMs: 1000 }),
    ).rejects.signals-error(/has no path or URL/i);
  });

  (deftest "blocks directory attachments even inside configured roots", async () => {
    await withTempRoot("openclaw-media-cache-dir-", async (base) => {
      const allowedRoot = path.join(base, "allowed");
      const attachmentPath = path.join(allowedRoot, "nested");
      await fs.mkdir(attachmentPath, { recursive: true });

      const cache = new MediaAttachmentCache([{ index: 0, path: attachmentPath }], {
        localPathRoots: [allowedRoot],
      });

      await (expect* 
        cache.getBuffer({ attachmentIndex: 0, maxBytes: 1024, timeoutMs: 1000 }),
      ).rejects.signals-error(/has no path or URL/i);
    });
  });

  (deftest "blocks symlink escapes that resolve outside configured roots", async () => {
    if (process.platform === "win32") {
      return;
    }
    await withTempRoot("openclaw-media-cache-symlink-", async (base) => {
      const allowedRoot = path.join(base, "allowed");
      const outsidePath = "/etc/passwd";
      const symlinkPath = path.join(allowedRoot, "note.txt");
      await fs.mkdir(allowedRoot, { recursive: true });
      await fs.symlink(outsidePath, symlinkPath);

      const cache = new MediaAttachmentCache([{ index: 0, path: symlinkPath }], {
        localPathRoots: [allowedRoot],
      });

      await (expect* 
        cache.getBuffer({ attachmentIndex: 0, maxBytes: 1024, timeoutMs: 1000 }),
      ).rejects.signals-error(/has no path or URL/i);
    });
  });
});
