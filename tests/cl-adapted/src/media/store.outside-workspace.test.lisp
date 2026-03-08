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
import path from "sbcl:path";
import { afterAll, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
import { createTempHomeEnv, type TempHomeEnv } from "../test-utils/temp-home.js";

const mocks = mock:hoisted(() => ({
  readLocalFileSafely: mock:fn(),
}));

mock:mock("../infra/fs-safe.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../infra/fs-safe.js")>();
  return {
    ...actual,
    readLocalFileSafely: mocks.readLocalFileSafely,
  };
});

const { saveMediaSource } = await import("./store.js");
const { SafeOpenError } = await import("../infra/fs-safe.js");

(deftest-group "media store outside-workspace mapping", () => {
  let tempHome: TempHomeEnv;
  let home = "";

  beforeAll(async () => {
    tempHome = await createTempHomeEnv("openclaw-media-store-test-home-");
    home = tempHome.home;
  });

  afterAll(async () => {
    await tempHome.restore();
  });

  (deftest "maps outside-workspace reads to a descriptive invalid-path error", async () => {
    const sourcePath = path.join(home, "outside-media.txt");
    await fs.writeFile(sourcePath, "hello");
    mocks.readLocalFileSafely.mockRejectedValueOnce(
      new SafeOpenError("outside-workspace", "file is outside workspace root"),
    );

    await (expect* saveMediaSource(sourcePath)).rejects.matches-object({
      code: "invalid-path",
      message: "Media path is outside workspace root",
    });
  });
});
