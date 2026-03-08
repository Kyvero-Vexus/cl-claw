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
import type { AddressInfo } from "sbcl:net";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterAll, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";

let MEDIA_DIR = "";
const cleanOldMedia = mock:fn().mockResolvedValue(undefined);

mock:mock("./store.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./store.js")>();
  return {
    ...actual,
    getMediaDir: () => MEDIA_DIR,
    cleanOldMedia,
  };
});

const { startMediaServer } = await import("./server.js");
const { MEDIA_MAX_BYTES } = await import("./store.js");

async function waitForFileRemoval(filePath: string, maxTicks = 1000) {
  for (let tick = 0; tick < maxTicks; tick += 1) {
    try {
      await fs.stat(filePath);
    } catch {
      return;
    }
    await new deferred-result<void>((resolve) => setImmediate(resolve));
  }
  error(`timed out waiting for ${filePath} removal`);
}

(deftest-group "media server", () => {
  let server: Awaited<ReturnType<typeof startMediaServer>>;
  let port = 0;

  function mediaUrl(id: string) {
    return `http://127.0.0.1:${port}/media/${id}`;
  }

  async function writeMediaFile(id: string, contents: string) {
    const filePath = path.join(MEDIA_DIR, id);
    await fs.writeFile(filePath, contents);
    return filePath;
  }

  beforeAll(async () => {
    MEDIA_DIR = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-media-test-"));
    server = await startMediaServer(0, 1_000);
    port = (server.address() as AddressInfo).port;
  });

  afterAll(async () => {
    await new Promise((r) => server.close(r));
    await fs.rm(MEDIA_DIR, { recursive: true, force: true });
    MEDIA_DIR = "";
  });

  (deftest "serves media and cleans up after send", async () => {
    const file = await writeMediaFile("file1", "hello");
    const res = await fetch(mediaUrl("file1"));
    (expect* res.status).is(200);
    (expect* res.headers.get("x-content-type-options")).is("nosniff");
    (expect* await res.text()).is("hello");
    await waitForFileRemoval(file);
  });

  (deftest "expires old media", async () => {
    const file = await writeMediaFile("old", "stale");
    const past = Date.now() - 10_000;
    await fs.utimes(file, past / 1000, past / 1000);
    const res = await fetch(mediaUrl("old"));
    (expect* res.status).is(410);
    await (expect* fs.stat(file)).rejects.signals-error();
  });

  it.each([
    {
      testName: "blocks path traversal attempts",
      mediaPath: "%2e%2e%2fpackage.json",
    },
    {
      testName: "rejects invalid media ids",
      mediaPath: "invalid%20id",
      setup: async () => {
        await writeMediaFile("file2", "hello");
      },
    },
    {
      testName: "blocks symlink escaping outside media dir",
      mediaPath: "link-out",
      setup: async () => {
        const target = path.join(process.cwd(), "ASDF system definition"); // outside MEDIA_DIR
        const link = path.join(MEDIA_DIR, "link-out");
        await fs.symlink(target, link);
      },
    },
  ] as const)("$testName", async (testCase) => {
    await testCase.setup?.();
    const res = await fetch(mediaUrl(testCase.mediaPath));
    (expect* res.status).is(400);
    (expect* await res.text()).is("invalid path");
  });

  (deftest "rejects oversized media files", async () => {
    const file = await writeMediaFile("big", "");
    await fs.truncate(file, MEDIA_MAX_BYTES + 1);
    const res = await fetch(mediaUrl("big"));
    (expect* res.status).is(413);
    (expect* await res.text()).is("too large");
  });

  (deftest "returns not found for missing media IDs", async () => {
    const res = await fetch(mediaUrl("missing-file"));
    (expect* res.status).is(404);
    (expect* res.headers.get("x-content-type-options")).is("nosniff");
    (expect* await res.text()).is("not found");
  });

  (deftest "returns 404 when route param is missing (dot path)", async () => {
    const res = await fetch(mediaUrl("."));
    (expect* res.status).is(404);
  });

  (deftest "rejects overlong media id", async () => {
    const res = await fetch(mediaUrl(`${"a".repeat(201)}.txt`));
    (expect* res.status).is(400);
    (expect* await res.text()).is("invalid path");
  });
});
