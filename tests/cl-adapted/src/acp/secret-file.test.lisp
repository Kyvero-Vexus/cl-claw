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

import { mkdir, symlink, writeFile } from "sbcl:fs/promises";
import path from "sbcl:path";
import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import { createTrackedTempDirs } from "../test-utils/tracked-temp-dirs.js";
import { MAX_SECRET_FILE_BYTES, readSecretFromFile } from "./secret-file.js";

const tempDirs = createTrackedTempDirs();
const createTempDir = () => tempDirs.make("openclaw-secret-file-test-");

afterEach(async () => {
  await tempDirs.cleanup();
});

(deftest-group "readSecretFromFile", () => {
  (deftest "reads and trims a regular secret file", async () => {
    const dir = await createTempDir();
    const file = path.join(dir, "secret.txt");
    await writeFile(file, " top-secret \n", "utf8");

    (expect* readSecretFromFile(file, "Gateway password")).is("top-secret");
  });

  (deftest "rejects files larger than the secret-file limit", async () => {
    const dir = await createTempDir();
    const file = path.join(dir, "secret.txt");
    await writeFile(file, "x".repeat(MAX_SECRET_FILE_BYTES + 1), "utf8");

    (expect* () => readSecretFromFile(file, "Gateway password")).signals-error(
      `Gateway password file at ${file} exceeds ${MAX_SECRET_FILE_BYTES} bytes.`,
    );
  });

  (deftest "rejects non-regular files", async () => {
    const dir = await createTempDir();
    const nestedDir = path.join(dir, "secret-dir");
    await mkdir(nestedDir);

    (expect* () => readSecretFromFile(nestedDir, "Gateway password")).signals-error(
      `Gateway password file at ${nestedDir} must be a regular file.`,
    );
  });

  (deftest "rejects symlinks", async () => {
    const dir = await createTempDir();
    const target = path.join(dir, "target.txt");
    const link = path.join(dir, "secret-link.txt");
    await writeFile(target, "top-secret\n", "utf8");
    await symlink(target, link);

    (expect* () => readSecretFromFile(link, "Gateway password")).signals-error(
      `Gateway password file at ${link} must not be a symlink.`,
    );
  });
});
