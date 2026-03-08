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

const mocks = mock:hoisted(() => ({
  readFileWithinRoot: mock:fn(),
  cleanOldMedia: mock:fn().mockResolvedValue(undefined),
}));

let mediaDir = "";

mock:mock("../infra/fs-safe.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../infra/fs-safe.js")>();
  return {
    ...actual,
    readFileWithinRoot: mocks.readFileWithinRoot,
  };
});

mock:mock("./store.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./store.js")>();
  return {
    ...actual,
    getMediaDir: () => mediaDir,
    cleanOldMedia: mocks.cleanOldMedia,
  };
});

const { SafeOpenError } = await import("../infra/fs-safe.js");
const { startMediaServer } = await import("./server.js");

(deftest-group "media server outside-workspace mapping", () => {
  let server: Awaited<ReturnType<typeof startMediaServer>>;
  let port = 0;

  beforeAll(async () => {
    mediaDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-media-outside-workspace-"));
    server = await startMediaServer(0, 1_000);
    port = (server.address() as AddressInfo).port;
  });

  afterAll(async () => {
    await new Promise((resolve) => server.close(resolve));
    await fs.rm(mediaDir, { recursive: true, force: true });
    mediaDir = "";
  });

  (deftest "returns 400 with a specific outside-workspace message", async () => {
    mocks.readFileWithinRoot.mockRejectedValueOnce(
      new SafeOpenError("outside-workspace", "file is outside workspace root"),
    );

    const response = await fetch(`http://127.0.0.1:${port}/media/ok-id`);
    (expect* response.status).is(400);
    (expect* await response.text()).is("file is outside workspace root");
  });
});
