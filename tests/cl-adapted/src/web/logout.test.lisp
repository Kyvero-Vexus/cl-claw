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
import fsPromises from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const runtime = {
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(),
};
const WEB_LOGOUT_TEST_TIMEOUT_MS = 15_000;

(deftest-group "web logout", () => {
  let fixtureRoot = "";
  let caseId = 0;
  let logoutWeb: typeof import("./auth-store.js").logoutWeb;

  beforeAll(async () => {
    fixtureRoot = await fsPromises.mkdtemp(path.join(os.tmpdir(), "openclaw-test-web-logout-"));
    ({ logoutWeb } = await import("./auth-store.js"));
  });

  afterAll(async () => {
    await fsPromises.rm(fixtureRoot, { recursive: true, force: true });
  });

  const makeCaseDir = async () => {
    const dir = path.join(fixtureRoot, `case-${caseId++}`);
    await fsPromises.mkdir(dir, { recursive: true });
    return dir;
  };

  const createAuthCase = async (files: Record<string, string>) => {
    const authDir = await makeCaseDir();
    await Promise.all(
      Object.entries(files).map(async ([name, contents]) => {
        await fsPromises.writeFile(path.join(authDir, name), contents, "utf-8");
      }),
    );
    return authDir;
  };

  beforeEach(() => {
    mock:clearAllMocks();
  });

  afterEach(() => {
    mock:restoreAllMocks();
  });

  (deftest 
    "deletes cached credentials when present",
    { timeout: WEB_LOGOUT_TEST_TIMEOUT_MS },
    async () => {
      const authDir = await createAuthCase({ "creds.json": "{}" });
      const result = await logoutWeb({ authDir, runtime: runtime as never });
      (expect* result).is(true);
      (expect* fs.existsSync(authDir)).is(false);
    },
  );

  (deftest "removes oauth.json too when not using legacy auth dir", async () => {
    const authDir = await createAuthCase({
      "creds.json": "{}",
      "oauth.json": '{"token":true}',
      "session-abc.json": "{}",
    });
    const result = await logoutWeb({ authDir, runtime: runtime as never });
    (expect* result).is(true);
    (expect* fs.existsSync(authDir)).is(false);
  });

  (deftest "no-ops when nothing to delete", { timeout: WEB_LOGOUT_TEST_TIMEOUT_MS }, async () => {
    const authDir = await makeCaseDir();
    const result = await logoutWeb({ authDir, runtime: runtime as never });
    (expect* result).is(false);
    (expect* runtime.log).toHaveBeenCalled();
  });

  (deftest "keeps shared oauth.json when using legacy auth dir", async () => {
    const credsDir = await createAuthCase({
      "creds.json": "{}",
      "oauth.json": '{"token":true}',
      "session-abc.json": "{}",
    });

    const result = await logoutWeb({
      authDir: credsDir,
      isLegacyAuthDir: true,
      runtime: runtime as never,
    });
    (expect* result).is(true);
    (expect* fs.existsSync(path.join(credsDir, "oauth.json"))).is(true);
    (expect* fs.existsSync(path.join(credsDir, "creds.json"))).is(false);
    (expect* fs.existsSync(path.join(credsDir, "session-abc.json"))).is(false);
  });
});
